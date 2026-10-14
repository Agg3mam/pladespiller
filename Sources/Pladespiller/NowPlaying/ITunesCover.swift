import Foundation

/// Cover via Apples offentlige iTunes-søgning, når Musik ikke selv udleverer det (streamede Apple Music-sange melder
/// 0 covers via AppleScript). Brugeren har sagt ja: kun titel, kunstner og album sendes til itunes.apple.com, kun
/// når Musik intet cover har, og hvert svar huskes (også "intet"), så samme sang ikke slås op igen.
final class ITunesCoverLookup {
    private var cache: [String: String?] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Cover-url (640 px) for sangen, eller nil.
    func coverURL(title: String, artist: String, album: String) async -> String? {
        let key = "\(title)|\(artist)|\(album)".lowercased()
        if let hit = cache[key] { return hit }
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let t0 = Date()
        var result: String?
        // Først Macens eget land, derefter Danmark (danske kunstnere findes ikke altid i alle lande).
        let region = Locale.current.region?.identifier.lowercased() ?? "dk"
        for country in Array(Set([region, "dk"])).sorted(by: { a, _ in a == region }) {
            guard let url = Self.searchURL(title: title, artist: artist, country: country) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    NowPlayingLog.log("[musik] iTunes-opslag: HTTP \(http.statusCode)")
                    continue
                }
                if let art = Self.bestArtwork(data, title: title, artist: artist, album: album) {
                    result = Self.largeArtworkURL(art)
                    break
                }
            } catch {
                NowPlayingLog.log("[musik] iTunes-opslag fejlede: \(error.localizedDescription)")
            }
        }
        NowPlayingLog.log("[musik] iTunes-opslag \(Int(Date().timeIntervalSince(t0) * 1000)) ms: " + (result ?? "intet"))
        cache[key] = result
        return result
    }

    nonisolated static func searchURL(title: String, artist: String, country: String) -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/search")
        c?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: country),
        ]
        return c?.url
    }

    /// Bedste match: samme titel og kunstner (uden store/små bogstaver og "- Remaster"-endelser), helst samme album.
    nonisolated static func bestArtwork(_ data: Data, title: String, artist: String, album: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        func norm(_ s: String) -> String {
            var t = s.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
            for cut in [" - ", " (", " ["] { if let r = t.range(of: cut) { t = String(t[..<r.lowerBound]) } }
            return t.trimmingCharacters(in: .whitespaces)
        }
        let nt = norm(title), na = norm(artist), nal = norm(album)
        var best: (score: Int, art: String)?
        for r in results {
            guard let art = r["artworkUrl100"] as? String, art.hasPrefix("https://") else { continue }
            let rt = norm(r["trackName"] as? String ?? ""), ra = norm(r["artistName"] as? String ?? "")
            let ral = norm(r["collectionName"] as? String ?? "")
            var score = 0
            if ra == na || ra.contains(na) || na.contains(ra) { score += 2 } else { continue }   // kunstneren skal passe
            if rt == nt { score += 2 } else if rt.contains(nt) || nt.contains(rt) { score += 1 }
            if !nal.isEmpty, ral == nal { score += 2 }
            if score >= 3, score > (best?.score ?? 0) { best = (score, art) }
        }
        return best?.art
    }

    /// iTunes giver 100 px; samme billede findes i 640 px.
    nonisolated static func largeArtworkURL(_ url: String) -> String {
        url.replacingOccurrences(of: "100x100bb", with: "640x640bb")
    }
}
