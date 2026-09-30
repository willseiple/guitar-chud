import Foundation

// MARK: - Title cleanup
//
// Spotify titles carry a lot of noise that torpedoes a chord search:
//   "El Scorcho - Live at Reading Festival / 1996"  ->  "El Scorcho"
//   "Dreams (feat. Stevie Nicks) - 2004 Remaster"   ->  "Dreams"
enum Clean {

    private static let titlePatterns = [
        #"\s*[-–—]\s*(live|remaster(ed)?|remix|mono|stereo|acoustic|demo|instrumental|karaoke|radio edit|single version|album version|edit|reprise|bonus track|deluxe|anniversary|expanded|re-?recorded|taylor'?s version)\b.*$"#,
        #"\s*[-–—]\s*(19|20)\d{2}\s*(remaster(ed)?|version|mix|digital remaster).*$"#,
        #"\s*[-–—]\s*from\s+["“].*$"#,
        #"\s*[-–—]\s*(recorded\s+)?live\s+(at|from|in)\b.*$"#,
        #"\s*\((feat\.?|ft\.?|featuring|with)\s[^)]*\)"#,
        #"\s*\[(feat\.?|ft\.?|featuring|with)\s[^\]]*\]"#,
        #"\s*\([^)]*(remaster(ed)?|remix|live|version|edit|mono|stereo|explicit|bonus|deluxe|acoustic|demo|instrumental|karaoke|re-?recorded)[^)]*\)"#,
        #"\s*\[[^\]]*(remaster(ed)?|remix|live|version|edit|explicit|bonus|deluxe)[^\]]*\]"#,
        #"\s*[-–—]\s*single$"#,
    ]

    static func title(_ s: String) -> String {
        var out = s
        for p in titlePatterns { out = out.replacing(regex: p, with: "", caseInsensitive: true) }
        out = out.replacing(regex: #"\s*\(\s*\)\s*"#, with: " ")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? s : out
    }

    /// Ultimate Guitar indexes one primary artist, so drop the featured crowd.
    static func artist(_ s: String) -> String {
        var out = s
        out = out.replacing(regex: #"\s*\(?(feat\.?|ft\.?|featuring|with)\s.*$"#, with: "", caseInsensitive: true)
        out = out.replacing(regex: #"\s*[,&×xX]\s+.*$"#, with: "")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? s : out
    }

    /// Loose form used only for comparing two names for equality.
    static func fold(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.replacing(regex: #"[^a-z0-9]+"#, with: "")
    }
}

extension String {
    func replacing(regex: String, with repl: String, caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: regex, options: opts) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: repl)
    }
}

// MARK: - HTML entities
//
// UG's stored tab text sometimes contains raw HTML entities ("can&rsquo;t",
// "&lt;"). They have to be decoded before anything renders or measures the
// text: "&rsquo;" is seven characters wide but one character on screen, so
// leaving it in would also shove every chord above it out of alignment.
enum Entities {

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "rsquo": "\u{2019}", "lsquo": "\u{2018}",
        "rdquo": "\u{201D}", "ldquo": "\u{201C}", "sbquo": "\u{201A}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}",
        "bull": "\u{2022}", "middot": "\u{00B7}", "deg": "\u{00B0}",
        "trade": "\u{2122}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "prime": "\u{2032}", "flat": "\u{266D}", "sharp": "\u{266F}",
        "eacute": "\u{00E9}", "egrave": "\u{00E8}", "agrave": "\u{00E0}",
        "uuml": "\u{00FC}", "ouml": "\u{00F6}", "auml": "\u{00E4}",
        "ntilde": "\u{00F1}", "ccedil": "\u{00E7}", "oslash": "\u{00F8}",
    ]

    private static let pattern = try? NSRegularExpression(
        pattern: #"&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,10});"#)

    /// One left-to-right pass, so "&amp;lt;" becomes "&lt;" rather than "<".
    static func decode(_ s: String) -> String {
        guard s.contains("&"), let pattern else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        pattern.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            out += value(of: body) ?? ns.substring(with: m.range)   // unknown: leave as written
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func value(of body: String) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            guard let v = UInt32(body.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        if body.hasPrefix("#") {
            guard let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        return named[body.lowercased()]
    }
}

// MARK: - Models

struct UGVersion {
    var songName = ""
    var artistName = ""
    var type = ""            // "Chords", "Tabs", "Ukulele", ...
    var url = ""
    var rating: Double = 0
    var votes: Int = 0
    var version: Int = 0
    var score: Double = 0

    var dict: [String: Any] {
        ["songName": songName, "artistName": artistName, "type": type, "url": url,
         "rating": rating, "votes": votes, "version": version]
    }
}

struct UGTab {
    var songName = ""
    var artistName = ""
    var type = ""
    var url = ""
    var content = ""
    var capo: Int? = nil
    var key = ""
    var tuning = ""
    var difficulty = ""
    var votes = 0
    var rating: Double = 0
    /// UG's own fingering data, keyed by chord name -> list of voicings.
    var shapes: [String: Any] = [:]

    var dict: [String: Any] {
        var d: [String: Any] = ["songName": songName, "artistName": artistName, "type": type,
                                "url": url, "content": content, "key": key, "tuning": tuning,
                                "difficulty": difficulty, "votes": votes, "rating": rating,
                                "shapes": shapes]
        if let capo { d["capo"] = capo }
        return d
    }
}

enum UGError: LocalizedError {
    case network(String)
    case noStore
    case noResults

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .noStore: return "Ultimate Guitar returned a page we couldn't read."
        case .noResults: return "No chords found."
        }
    }
}

// MARK: - Client

final class UGClient {

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml",
        ]
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    // MARK: Fetching

    private func get(_ url: URL) throws -> String {
        var out: Result<String, Error>!
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: url) { data, resp, err in
            defer { sem.signal() }
            if let err { out = .failure(UGError.network(err.localizedDescription)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                let msg = code == 404
                    ? "That chord sheet is no longer on Ultimate Guitar."
                    : "Ultimate Guitar replied HTTP \(code)."
                out = .failure(UGError.network(msg)); return
            }
            guard let data, let s = String(data: data, encoding: .utf8) else {
                out = .failure(UGError.network("Unreadable response.")); return
            }
            out = .success(s)
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        guard let out else { throw UGError.network("Request timed out.") }
        return try out.get()
    }

    /// Every UG page ships its state as JSON inside <div class="js-store" data-content="...">.
    private func store(from html: String) throws -> [String: Any] {
        guard let re = try? NSRegularExpression(pattern: #"<div class="js-store" data-content="(.*?)"></div>"#,
                                                options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html)
        else { throw UGError.noStore }

        let unescaped = String(html[r])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")   // must come last

        guard let data = unescaped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let page = json["store"] as? [String: Any],
              let p = page["page"] as? [String: Any],
              let d = p["data"] as? [String: Any]
        else { throw UGError.noStore }
        return d
    }

    // MARK: Search

    /// Ranked chord versions for a song. Best match first.
    func search(title: String, artist: String) throws -> [UGVersion] {
        let query = artist.isEmpty ? title : "\(artist) \(title)"
        var versions = try rawSearch(query)

        // Artist+title found nothing usable -> retry on title alone.
        if versions.isEmpty, !artist.isEmpty {
            versions = try rawSearch(title)
        }
        return rank(versions, title: title, artist: artist)
    }

    func rawSearch(_ query: String) throws -> [UGVersion] {
        var cs = URLComponents(string: "https://www.ultimate-guitar.com/search.php")!
        cs.queryItems = [
            URLQueryItem(name: "search_type", value: "title"),
            URLQueryItem(name: "value", value: query),
        ]
        guard let url = cs.url else { throw UGError.network("Bad search URL.") }

        let data = try store(from: try get(url))
        let results = (data["results"] as? [[String: Any]]) ?? []

        return results.compactMap { r in
            guard let url = r["tab_url"] as? String else { return nil }
            // /pro/ links are paid interactive tabs with no readable chord text.
            guard !url.contains("/pro/") else { return nil }
            guard let type = r["type"] as? String else { return nil }

            var v = UGVersion()
            v.songName = Entities.decode((r["song_name"] as? String) ?? "")
            v.artistName = Entities.decode((r["artist_name"] as? String) ?? "")
            v.type = type
            v.url = url
            v.rating = (r["rating"] as? Double) ?? 0
            v.votes = (r["votes"] as? Int) ?? 0
            v.version = (r["version"] as? Int) ?? 0
            return v
        }
    }

    /// Prefer real chord sheets for the right song by the right artist, well-rated by many people.
    private func rank(_ versions: [UGVersion], title: String, artist: String) -> [UGVersion] {
        let wantTitle = Clean.fold(title)
        let wantArtist = Clean.fold(artist)

        var scored = versions.map { v -> UGVersion in
            var v = v
            var s = 0.0

            switch v.type.lowercased() {
            case "chords":         s += 100
            case "ukulele chords": s += 20
            case "tabs":           s += 15
            case "bass tabs":      s += 5
            default:               s += 0
            }

            let gotTitle = Clean.fold(v.songName)
            if gotTitle == wantTitle { s += 40 }
            else if gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) { s += 18 }

            let gotArtist = Clean.fold(v.artistName)
            if !wantArtist.isEmpty {
                if gotArtist == wantArtist { s += 40 }
                else if gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist) { s += 15 }
            }

            // Confidence-weighted rating: 4.9 from 250 votes beats 5.0 from 2.
            s += v.rating * log(Double(v.votes) + 1) * 2.0

            v.score = s
            return v
        }

        scored.sort { $0.score > $1.score }
        return scored
    }

    // MARK: Tab page

    func fetchTab(url: String) throws -> UGTab {
        guard let u = URL(string: url) else { throw UGError.network("Bad tab URL.") }
        let data = try store(from: try get(u))

        var t = UGTab()
        t.url = url

        if let tab = data["tab"] as? [String: Any] {
            t.songName = Entities.decode((tab["song_name"] as? String) ?? "")
            t.artistName = Entities.decode((tab["artist_name"] as? String) ?? "")
            t.type = (tab["type"] as? String) ?? ""
            t.difficulty = (tab["difficulty"] as? String) ?? ""
            t.key = (tab["tonality_name"] as? String) ?? ""
            t.tuning = (tab["tuning"] as? String) ?? ""
            t.votes = (tab["votes"] as? Int) ?? 0
            t.rating = (tab["rating"] as? Double) ?? 0
            if let capo = tab["capo"] as? Int, capo > 0 { t.capo = capo }
        }

        if let view = data["tab_view"] as? [String: Any] {
            if let wiki = view["wiki_tab"] as? [String: Any],
               let content = wiki["content"] as? String {
                t.content = Entities.decode(content)
            }
            if let app = view["applicature"] as? [String: Any] {
                t.shapes = app
            }
            if t.tuning.isEmpty, let meta = view["meta"] as? [String: Any],
               let tuning = meta["tuning"] as? [String: Any],
               let name = tuning["name"] as? String {
                t.tuning = name
            }
        }

        guard !t.content.isEmpty else { throw UGError.noResults }
        return t
    }
}
