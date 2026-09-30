import Foundation
import AppKit

struct SpotifyTrack: Equatable {
    var id = ""
    var name = ""
    var artist = ""
    var album = ""
    var playing = false
    var position: Double = 0   // seconds
    var duration: Double = 0   // seconds
}

enum SpotifyState {
    case notRunning
    case notAuthorized
    case failed(String)
    case ok(SpotifyTrack)
}

/// Reads the currently playing track straight out of Spotify.app over Apple Events.
/// No API keys, no OAuth -- but the first read triggers a one-time Automation prompt.
final class SpotifyWatcher {

    private static let sep = "\u{1F}"

    private lazy var script: NSAppleScript? = NSAppleScript(source: """
    tell application id "com.spotify.client"
        set d to ASCII character 31
        set playState to player state as text
        set tid to ""
        set nm to ""
        set ar to ""
        set al to ""
        set dur to 0
        set pos to 0
        try
            set tid to id of current track
            set nm to name of current track
            set ar to artist of current track
            set al to album of current track
            set dur to duration of current track
            set pos to player position
        end try
        return tid & d & nm & d & ar & d & al & d & playState & d & (dur as text) & d & (pos as text)
    end tell
    """)

    /// True when Spotify is already up. Checked first so we never *launch* Spotify.
    private var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    func read() -> SpotifyState {
        guard spotifyIsRunning else { return .notRunning }
        guard let script else { return .failed("Could not compile the Spotify script.") }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: user hasn't granted Automation access. -600/-609: app went away mid-read.
            if code == -1743 { return .notAuthorized }
            if code == -600 || code == -609 { return .notRunning }
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Apple Event error \(code)"
            return .failed(msg)
        }

        guard let raw = result.stringValue else { return .failed("Spotify returned nothing.") }
        let f = raw.components(separatedBy: Self.sep)
        guard f.count >= 7 else { return .failed("Unexpected reply from Spotify.") }

        var t = SpotifyTrack()
        t.id = f[0]
        t.name = f[1]
        t.artist = f[2]
        t.album = f[3]
        t.playing = f[4].lowercased() == "playing"
        t.duration = (Double(f[5]) ?? 0) / 1000.0   // Spotify reports milliseconds
        t.position = Double(f[6]) ?? 0
        return .ok(t)
    }
}
