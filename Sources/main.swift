import AppKit
import WebKit

/// WKWebView eats mouse events, so `isMovableByWindowBackground` never fires and
/// the window can't be dragged. This transparent strip sits above the web view
/// over the bar's dead space and drags the window itself.
final class DragView: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)          // match the usual titlebar double-click
        } else {
            window?.performDrag(with: event)
        }
    }
    /// Stay out of the way until the page has told us where to sit.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.width < 1 || bounds.height < 1 ? nil : super.hitTest(point)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {

    private var window: NSWindow!
    private var web: WKWebView!
    private var dragViews: [DragView] = []
    private var cmdDragMonitor: Any?
    private var dragHost: NSView!
    private var statusItem: NSStatusItem!

    private let spotify = SpotifyWatcher()
    private let ug = UGClient()
    private let work = DispatchQueue(label: "guitarhud.ug", qos: .userInitiated)

    private var pollTimer: Timer?
    private var webReady = false
    private var pendingPush: [String: Any]?

    // Current state
    private var track = SpotifyTrack()
    private var versions: [UGVersion] = []
    private var tab: UGTab?
    private var statusKind = "idle"
    private var statusMessage = ""
    private var pinned = true

    /// Bumped on every track change so a slow in-flight fetch can't overwrite a newer song.
    private var generation = 0

    /// The track we've already looked up. A song gets one automatic attempt;
    /// without this, a failed lookup re-fires on every poll tick.
    private var attemptedTrackID: String?

    /// Remembers the version you picked, per song, so re-hearing a track restores your choice.
    private var chosenByTrack: [String: String] = [:]
    private var tabCache: [String: UGTab] = [:]

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindow()
        buildStatusItem()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        pollTimer?.tolerance = 0.25
        poll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // Closing the window leaves the app alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    // MARK: Window

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)

        w.title = "GuitarCHUD"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 300, height: 220)
        w.delegate = self
        w.setFrameAutosaveName("GuitarHUDWindow")
        w.isReleasedWhenClosed = false

        // The FaceTime trick: float above normal windows, and stay visible on every
        // Space including other apps' fullscreen ones.
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "bridge")
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")   // let the HTML own the background
        if v.responds(to: Selector(("setInspectable:"))) { v.setValue(true, forKey: "inspectable") }

        // Web view fills the window; the drag handle rides above it.
        let container = NSView(frame: NSRect(origin: .zero, size: w.frame.size))
        v.frame = container.bounds
        v.autoresizingMask = [.width, .height]
        container.addSubview(v)

        w.contentView = container
        web = v
        dragHost = container

        if let html = Bundle.main.url(forResource: "ui", withExtension: "html") {
            v.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        } else {
            v.loadHTMLString("<h3 style='font:13px -apple-system;padding:20px'>ui.html missing from the app bundle.</h3>", baseURL: nil)
        }

        window = w
        placeSensibly(w)
        w.makeKeyAndOrderFront(nil)

        // ⌘-drag moves the window from anywhere, including over the chord sheet --
        // which stays fully interactive for scrolling, selection and chord popups,
        // so it can't be covered by a drag strip.
        cmdDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let win = self.window, event.window === win,
                  event.modifierFlags.contains(.command) else { return event }
            win.performDrag(with: event)
            return nil   // consumed: don't also deliver it to the page
        }

        NSLog("GuitarCHUD window visible=%d frame=%@ screens=%d",
              w.isVisible ? 1 : 0, NSStringFromRect(w.frame), NSScreen.screens.count)
    }


    /// A restored frame can end up off screen or jammed into a corner. Nudge it
    /// back somewhere usable, defaulting to the top-right like a PiP tile.
    private func placeSensibly(_ w: NSWindow) {
        guard let vis = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = w.frame

        let degenerate = f.origin == .zero || f.minX < vis.minX + 4 || f.minY < vis.minY + 4
        if degenerate {
            f.size = NSSize(width: max(f.width, 470), height: max(f.height, 560))
            f.origin = NSPoint(x: vis.maxX - f.width - 24, y: vis.maxY - f.height - 24)
        }
        // Clamp so it can never be dragged/restored fully off screen.
        f.origin.x = min(max(f.origin.x, vis.minX), vis.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vis.minY), vis.maxY - f.height)
        w.setFrame(f, display: false)
    }

    /// Lay out the transparent drag strips the page asked for, adding views as
    /// the count grows and parking the spares out of the way.
    private func setDragFrames(_ frames: [NSRect]) {
        while dragViews.count < frames.count {
            let v = DragView(frame: .zero)
            v.autoresizingMask = [.minYMargin]   // stays pinned to the top during a resize
            dragHost.addSubview(v, positioned: .above, relativeTo: web)
            dragViews.append(v)
        }
        for (i, v) in dragViews.enumerated() {
            v.isHidden = i >= frames.count
            if i < frames.count { v.frame = frames[i] }
        }
    }

    /// Clicking the Dock icon brings the chord window back after you close it.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)      // hide, don't destroy -- menu bar keeps working
        return false
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎸"
        rebuildStatusMenu()
    }

    /// The drop-down: current song on top, then one click per available version.
    private func rebuildStatusMenu() {
        let menu = NSMenu()

        let header: String
        switch statusKind {
        case "notRunning":    header = "Spotify isn’t running"
        case "notAuthorized": header = "Automation permission needed"
        case "loading":       header = "Looking up chords…"
        case "noResults":     header = "No chords for this song"
        default:
            header = track.name.isEmpty ? "Nothing playing" : "\(track.name) — \(track.artist)"
        }
        let head = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)

        if !versions.isEmpty {
            menu.addItem(.separator())
            let label = NSMenuItem(title: "Versions", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)

            for v in versions.prefix(8) {
                let stars = v.votes > 0 ? String(format: "★%.1f (%d)", v.rating, v.votes) : "unrated"
                let title = "  \(v.type) v\(v.version > 0 ? String(v.version) : "1")  ·  \(stars)"
                let item = NSMenuItem(title: title, action: #selector(menuPickVersion(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = v.url
                if v.url == tab?.url { item.state = .on }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Chord Window", action: #selector(menuShow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let refresh = NSMenuItem(title: "Look Up Again", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let pin = NSMenuItem(title: "Float Above Other Windows", action: #selector(menuTogglePin), keyEquivalent: "")
        pin.target = self
        pin.state = pinned ? .on : .off
        menu.addItem(pin)

        if let url = tab?.url {
            let open = NSMenuItem(title: "Open on Ultimate Guitar", action: #selector(menuOpenWeb(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = url
            menu.addItem(open)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit GuitarCHUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func menuShow() { showWindow() }
    @objc private func menuRefresh() { lookUp(force: true) }

    @objc private func menuTogglePin() {
        pinned.toggle()
        applyPin()
        rebuildStatusMenu()
        push(newSong: false)
    }

    @objc private func menuPickVersion(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        showWindow()
        load(versionURL: url)
    }

    @objc private func menuOpenWeb(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    private func applyPin() {
        window.level = pinned ? .floating : .normal
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide GuitarCHUD", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit GuitarCHUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Needed so copy/paste works inside the in-page search field.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = main.item(at: 2)?.submenu
    }

    // MARK: Polling

    private func poll() {
        switch spotify.read() {
        case .notRunning:
            if statusKind != "notRunning" {
                statusKind = "notRunning"; statusMessage = ""
                track = SpotifyTrack(); versions = []; tab = nil
                attemptedTrackID = nil
                push(newSong: false); rebuildStatusMenu()
            }

        case .notAuthorized:
            if statusKind != "notAuthorized" {
                statusKind = "notAuthorized"
                statusMessage = "GuitarCHUD needs permission to read Spotify."
                attemptedTrackID = nil
                push(newSong: false); rebuildStatusMenu()
            }

        case .failed(let m):
            if statusKind != "error" || statusMessage != m {
                statusKind = "error"; statusMessage = m
                attemptedTrackID = nil          // Spotify-side; retry once it's back
                push(newSong: false); rebuildStatusMenu()
            }

        case .ok(let t):
            track = t

            // One automatic attempt per song. Retrying on every tick would hammer
            // Ultimate Guitar once a second and flicker the window between
            // "Finding chords…" and the failure. "Look Up Again" retries on purpose.
            if attemptedTrackID != t.id {
                versions = []; tab = nil
                lookUp(force: false)
            } else {
                tick()   // same song: just keep playback position fresh
            }
        }
    }

    /// Lightweight per-second update so scroll-sync can follow the song.
    private func tick() {
        guard webReady else { return }
        let payload: [String: Any] = [
            "position": track.position,
            "duration": track.duration,
            "playing": track.playing,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.GH && window.GH.tick(\(json))")
    }

    // MARK: Lookup

    private func lookUp(force: Bool) {
        attemptedTrackID = track.id     // counts even if it fails, so we stop here
        guard !track.name.isEmpty else {
            statusKind = "idle"; versions = []; tab = nil
            push(newSong: false); rebuildStatusMenu()
            return
        }

        generation += 1
        let gen = generation
        let title = Clean.title(track.name)
        let artist = Clean.artist(track.artist)
        let remembered = force ? nil : chosenByTrack[track.id]

        statusKind = "loading"
        statusMessage = ""
        push(newSong: true)
        rebuildStatusMenu()

        work.async { [weak self] in
            guard let self else { return }
            do {
                let found = try self.ug.search(title: title, artist: artist)
                guard !found.isEmpty else { throw UGError.noResults }

                // Search results can point at tabs that have since been pulled, so
                // walk down the ranking rather than handing back a 404.
                var order = found.map(\.url)
                if let remembered { order = [remembered] + order.filter { $0 != remembered } }

                var loadedTab: UGTab?
                var pick = ""
                var lastError: Error = UGError.noResults
                for url in order.prefix(4) {
                    do {
                        let t = try self.tabCache[url] ?? self.ug.fetchTab(url: url)
                        loadedTab = t
                        pick = url
                        break
                    } catch {
                        lastError = error
                        continue
                    }
                }
                guard let loaded = loadedTab else { throw lastError }

                DispatchQueue.main.async {
                    guard gen == self.generation else { return }   // a newer song won
                    self.tabCache[pick] = loaded
                    self.versions = found
                    self.tab = loaded
                    self.statusKind = "ok"
                    self.statusMessage = ""
                    self.push(newSong: true)
                    self.rebuildStatusMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.versions = []
                    self.tab = nil
                    var kind = "error"
                    if let ug = error as? UGError, case .noResults = ug { kind = "noResults" }
                    self.statusKind = kind
                    self.statusMessage = error.localizedDescription
                    self.push(newSong: true)
                    self.rebuildStatusMenu()
                }
            }
        }
    }

    private func load(versionURL: String) {
        generation += 1
        let gen = generation
        let trackID = track.id
        chosenByTrack[trackID] = versionURL

        statusKind = "loading"
        push(newSong: false)

        work.async { [weak self] in
            guard let self else { return }
            do {
                let loaded = try self.tabCache[versionURL] ?? self.ug.fetchTab(url: versionURL)
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.tabCache[versionURL] = loaded
                    self.tab = loaded
                    self.statusKind = "ok"
                    self.statusMessage = ""
                    self.push(newSong: false)
                    self.rebuildStatusMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.statusKind = "error"
                    self.statusMessage = error.localizedDescription
                    self.push(newSong: false)
                    self.rebuildStatusMenu()
                }
            }
        }
    }

    private func manualSearch(_ query: String) {
        generation += 1
        let gen = generation
        statusKind = "loading"
        statusMessage = ""
        push(newSong: false)

        work.async { [weak self] in
            guard let self else { return }
            do {
                let found = self.ug.rank_public(try self.ug.rawSearch(query), query: query)
                guard !found.isEmpty else { throw UGError.noResults }
                let loaded = try self.ug.fetchTab(url: found[0].url)
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.tabCache[found[0].url] = loaded
                    self.versions = found
                    self.tab = loaded
                    self.statusKind = "ok"
                    self.push(newSong: true)
                    self.rebuildStatusMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.statusKind = "error"
                    self.statusMessage = error.localizedDescription
                    self.push(newSong: false)
                    self.rebuildStatusMenu()
                }
            }
        }
    }

    // MARK: Bridge to the web view

    private func push(newSong: Bool) {
        var payload: [String: Any] = [
            "status": statusKind,
            "message": statusMessage,
            "pinned": pinned,
            "newSong": newSong,
            "track": [
                "id": track.id,
                "name": track.name,
                "artist": track.artist,
                "album": track.album,
                "cleanTitle": Clean.title(track.name),
                "cleanArtist": Clean.artist(track.artist),
                "playing": track.playing,
                "position": track.position,
                "duration": track.duration,
            ],
            "versions": versions.prefix(8).map(\.dict),
        ]
        payload["tab"] = tab?.dict as Any? ?? NSNull()

        guard webReady else { pendingPush = payload; return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.GH && window.GH.update(\(json))")
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "ready":
            webReady = true
            if let p = pendingPush,
               let data = try? JSONSerialization.data(withJSONObject: p),
               let json = String(data: data, encoding: .utf8) {
                web.evaluateJavaScript("window.GH && window.GH.update(\(json))")
                pendingPush = nil
            } else {
                push(newSong: false)
            }

        case "pickVersion":
            if let url = body["url"] as? String { load(versionURL: url) }

        case "search":
            if let q = (body["query"] as? String)?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
                manualSearch(q)
            }

        case "refresh":
            lookUp(force: true)

        case "setPin":
            pinned = (body["on"] as? Bool) ?? pinned
            applyPin()
            rebuildStatusMenu()

        case "dragRects":
            guard let list = body["rects"] as? [[String: Any]] else { break }
            let h = web.bounds.height
            var frames: [NSRect] = []
            for r in list {
                guard let x = r["x"] as? Double, let y = r["y"] as? Double,
                      let dw = r["w"] as? Double, let dh = r["h"] as? Double,
                      dw >= 8, dh >= 8 else { continue }   // skip degenerate strips
                // CSS coords run top-down; AppKit's run bottom-up.
                frames.append(NSRect(x: x, y: h - y - dh, width: dw, height: dh))
            }
            guard !frames.isEmpty else { break }           // never go undraggable
            setDragFrames(frames)

        case "openWeb":
            if let s = body["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }

        case "openAutomationSettings":
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(u)
            }

        default: break
        }
    }
}

// Expose ranking for manual searches, where there's no separate artist to weigh.
extension UGClient {
    func rank_public(_ versions: [UGVersion], query: String) -> [UGVersion] {
        versions.map { v -> UGVersion in
            var v = v
            var s = 0.0
            s += v.type.lowercased() == "chords" ? 100 : 10
            s += v.rating * log(Double(v.votes) + 1) * 2.0
            if Clean.fold(query).contains(Clean.fold(v.songName)) { s += 20 }
            v.score = s
            return v
        }.sorted { $0.score > $1.score }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
