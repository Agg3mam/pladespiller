import CryptoKit
import Foundation

// MARK: - LRC-parsning

/// Parser for LRC (og "enhanced LRC" med ord-timing). Ren funktion; testes i selvtesten.
enum LRCParser {
    /// `[mm:ss.xx]tekst`, flere tidsstempler pr. linje, `[offset:±ms]`, metadata-tags ignoreres,
    /// `<mm:ss.xx>ord` giver `words`, tom tekst = instrumentalt stykke. Sorteret efter tid.
    static func parse(_ lrc: String, trackKey: String) -> Lyrics {
        var entries: [(start: TimeInterval, order: Int, text: String, words: [Lyrics.Word])] = []
        var offset: TimeInterval = 0
        var order = 0
        for rawLine in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var stamps: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = time(tag) {
                    stamps.append(t)
                } else if let colon = tag.firstIndex(of: ":"),
                          tag[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "offset",
                          let ms = Double(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)) {
                    // Positiv offset = teksten skal komme tidligere.
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let (text, words) = enhanced(String(rest))
            for s in stamps {
                entries.append((s, order, text, words))
                order += 1
            }
        }
        let lines = entries
            .sorted { $0.start == $1.start ? $0.order < $1.order : $0.start < $1.start }
            .map { e in
                Lyrics.Line(start: max(0, e.start - offset), text: e.text,
                            words: e.words.map { Lyrics.Word(start: max(0, $0.start - offset), text: $0.text) })
            }
        return Lyrics(trackKey: trackKey, lines: lines)
    }

    /// `mm:ss`, `mm:ss.xx`, `mm:ss.xxx` eller `mm:ss:xx` → sekunder. nil for metadata-tags.
    static func time(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let m = Int(parts[0].trimmingCharacters(in: .whitespaces)), m >= 0 else { return nil }
        var secPart = String(parts[1])
        if parts.count == 3 { secPart += "." + parts[2] }
        guard let s = Double(secPart.trimmingCharacters(in: .whitespaces)), s >= 0, s < 60 + 1e-9,
              secPart.allSatisfy({ $0.isNumber || $0 == "." || $0 == " " }) else { return nil }
        return Double(m) * 60 + s
    }

    /// Fjerner `<mm:ss.xx>` ord-tags og returnerer (ren tekst, ord med tider).
    static func enhanced(_ text: String) -> (String, [Lyrics.Word]) {
        guard text.contains("<") else { return (text.trimmingCharacters(in: .whitespaces), []) }
        var words: [Lyrics.Word] = []
        var plain = ""
        var rest = Substring(text)
        var currentStart: TimeInterval?
        var currentText = ""
        func flush() {
            if let s = currentStart {
                let w = currentText.trimmingCharacters(in: .whitespaces)
                if !w.isEmpty { words.append(Lyrics.Word(start: s, text: w)) }
            }
            currentText = ""
        }
        while !rest.isEmpty {
            if rest.hasPrefix("<"), let close = rest.firstIndex(of: ">"),
               let t = time(rest[rest.index(after: rest.startIndex)..<close]) {
                flush()
                currentStart = t
                rest = rest[rest.index(after: close)...]
            } else {
                let c = rest.removeFirst()
                plain.append(c)
                currentText.append(c)
            }
        }
        flush()
        let clean = plain.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return (clean, words)
    }
}

// MARK: - Rensning af titler og valg af match

enum LyricsMatching {
    private static let noiseWords = ["remaster", "live", "version", "edit", "mix", "mono", "stereo", "deluxe",
                                     "bonus", "acoustic", "demo", "feat", "ft.", "with ", "from ", "anniversary",
                                     "single", "explicit", "clean", "instrumental", "re-recorded", "taylor's"]

    /// "Song - Remastered 2011" → "Song", "Song (feat. X)" → "Song", "Song - Live" → "Song".
    static func cleanTitle(_ title: String) -> String {
        var t = title
        // Parenteser/klammer med støjord.
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let o = t.range(of: open), let c = t.range(of: close, range: o.upperBound..<t.endIndex) {
                let inner = t[o.upperBound..<c.lowerBound].lowercased()
                guard noiseWords.contains(where: { inner.contains($0) }) else { break }
                t.removeSubrange(o.lowerBound..<c.upperBound)
            }
        }
        // " - …" med støjord.
        if let dash = t.range(of: " - ", options: .backwards) {
            let tail = t[dash.upperBound...].lowercased()
            if noiseWords.contains(where: { tail.contains($0) }) || tail.allSatisfy({ $0.isNumber || $0 == " " }) {
                t = String(t[..<dash.lowerBound])
            }
        }
        return t.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Første kunstner ("A, B" / "A & B" / "A feat. B" → "A").
    static func primaryArtist(_ artist: String) -> String {
        var a = artist
        for sep in [", ", " & ", " feat. ", " ft. ", " featuring ", " x ", " og ", " and "] {
            if let r = a.range(of: sep, options: .caseInsensitive) { a = String(a[..<r.lowerBound]) }
        }
        return a.trimmingCharacters(in: .whitespaces)
    }

    static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    struct Candidate: Equatable {
        var trackName: String
        var artistName: String
        var duration: TimeInterval?
        var syncedLyrics: String?
        var instrumental: Bool
    }

    /// Bedste søgeresultat: skal have syncedLyrics (eller være instrumental), varighed inden for ±2 s
    /// (hvis kendt) og ligne titel/kunstner. Tættest på varigheden vinder.
    static func bestMatch(_ candidates: [Candidate], title: String, artist: String, duration: TimeInterval?) -> Candidate? {
        let nt = normalized(cleanTitle(title)), na = normalized(primaryArtist(artist))
        let ok = candidates.filter { c in
            guard c.instrumental || !(c.syncedLyrics ?? "").isEmpty else { return false }
            if let d = duration, d > 0 {
                guard let cd = c.duration, abs(cd - d) <= 2 else { return false }
            }
            let ct = normalized(cleanTitle(c.trackName)), ca = normalized(c.artistName)
            let titleOK = !nt.isEmpty && (ct == nt || ct.contains(nt) || nt.contains(ct))
            let artistOK = na.isEmpty || ca.hasPrefix(na) || na.hasPrefix(ca)
            return titleOK && artistOK
        }
        return ok.min { a, b in
            let da = duration.flatMap { d in a.duration.map { abs($0 - d) } } ?? 0
            let db = duration.flatMap { d in b.duration.map { abs($0 - d) } } ?? 0
            if da != db { return da < db }
            return (a.syncedLyrics?.isEmpty == false) && (b.syncedLyrics?.isEmpty != false)
        }
    }
}

// MARK: - Cache

/// Det der gemmes pr. sang (hukommelse og disk).
struct LyricsCacheEntry: Codable, Equatable {
    var synced: String?        // nil = ikke fundet
    var instrumental = false
    var fetched: Date

    var isNotFound: Bool { synced == nil && !instrumental }
}

/// LRU i hukommelsen (~20) + JSON-filer på disk. "Ikke fundet" udløber efter 7 dage.
final class LyricsCache {
    static let notFoundLifetime: TimeInterval = 7 * 24 * 3600
    let directory: URL?
    let capacity: Int
    private var memory: [(key: String, entry: LyricsCacheEntry)] = []

    init(directory: URL? = LyricsCache.defaultDirectory, capacity: Int = 20) {
        self.directory = directory
        self.capacity = capacity
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dk.holgerskov.Pladespiller/lyrics", isDirectory: true)
    }

    /// Nøgle uafhængig af kilde-app: normaliseret titel|kunstner|album|varighed (hele sek.).
    static func key(title: String, artist: String, album: String, duration: TimeInterval) -> String {
        let raw = [LyricsMatching.normalized(title), LyricsMatching.normalized(artist),
                   LyricsMatching.normalized(album), String(Int(duration.rounded()))].joined(separator: "|")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var memoryKeys: [String] { memory.map(\.key) }

    func entry(for key: String, now: Date = .now) -> LyricsCacheEntry? {
        if let i = memory.firstIndex(where: { $0.key == key }) {
            let e = memory.remove(at: i)
            if expired(e.entry, now: now) { return nil }
            memory.insert(e, at: 0)
            return e.entry
        }
        guard let url = fileURL(key), let data = try? Data(contentsOf: url),
              let e = try? JSONDecoder().decode(LyricsCacheEntry.self, from: data) else { return nil }
        if expired(e, now: now) { try? FileManager.default.removeItem(at: url); return nil }
        remember(key, e)
        return e
    }

    func store(_ e: LyricsCacheEntry, for key: String) {
        remember(key, e)
        if let url = fileURL(key), let data = try? JSONEncoder().encode(e) { try? data.write(to: url, options: .atomic) }
    }

    private func remember(_ key: String, _ e: LyricsCacheEntry) {
        memory.removeAll { $0.key == key }
        memory.insert((key, e), at: 0)
        if memory.count > capacity { memory.removeLast(memory.count - capacity) }
    }

    private func expired(_ e: LyricsCacheEntry, now: Date) -> Bool {
        e.isNotFound && now.timeIntervalSince(e.fetched) > Self.notFoundLifetime
    }

    private func fileURL(_ key: String) -> URL? { directory?.appendingPathComponent(key + ".json") }
}

// MARK: - LRCLIB

/// Henter tidsindstillet sangtekst fra LRCLIB (lrclib.net). Sender kun titel, kunstner, album og varighed.
final class LyricsService {
    static let userAgent = "Pladespiller/0.3 (https://github.com/Agg3mam/pladespiller)"
    static let baseURL = URL(string: "https://lrclib.net/api/")!

    let cache: LyricsCache
    private let session: URLSession
    /// Nøgler LRCLIB har givet et endeligt svar på i denne kørsel (fundet / ikke fundet).
    private var answered: Set<String> = []
    /// Midlertidige fejl (5xx, 429, timeout, netværk) pr. sang i denne kørsel, og hvornår næste forsøg må ske.
    private var failures: [String: (count: Int, nextAllowed: Date)] = [:]
    private var inFlight: [String: Task<LyricsCacheEntry?, Never>] = [:]
    /// Til selvtesten: erstatter netværket (nil = midlertidig fejl) og uret.
    private let fetcher: ((Query) async -> LyricsCacheEntry?)?
    private let now: () -> Date

    init(cache: LyricsCache = LyricsCache(), fetcher: ((Query) async -> LyricsCacheEntry?)? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.cache = cache
        self.fetcher = fetcher
        self.now = now
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Accept": "application/json"]
        session = URLSession(configuration: config)
    }

    struct Query {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval   // 0 = ukendt (radio)
    }

    /// Kun fra cachen (ingen netværk).
    func cached(_ q: Query, trackKey: String) -> LyricsState? {
        cache.entry(for: LyricsCache.key(title: q.title, artist: q.artist, album: q.album, duration: q.duration))
            .map { Self.state(from: $0, trackKey: trackKey) }
    }

    /// Svar på et opslag: færdigt, eller "prøv igen om x s" efter en midlertidig fejl.
    enum Lookup: Equatable {
        case done(LyricsState)
        case retry(after: TimeInterval)
    }

    /// Ventetid før næste forsøg efter `failures` midlertidige fejl i træk: 15 s, 60 s, 5 min,
    /// derefter nil (opgiv for denne kørsel). Dvs. højst 3 nye forsøg efter det første.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval? {
        let delays: [TimeInterval] = [15, 60, 300]
        return failures >= 1 && failures <= delays.count ? delays[failures - 1] : nil
    }

    /// Fra cachen, ellers LRCLIB. Endelige svar hentes én gang pr. sang pr. kørsel; midlertidige fejl
    /// gemmes ikke på disk og giver `.retry` efter backoff-reglen.
    func lyrics(for q: Query, trackKey: String) async -> Lookup {
        let key = LyricsCache.key(title: q.title, artist: q.artist, album: q.album, duration: q.duration)
        if let e = cache.entry(for: key) { return .done(Self.state(from: e, trackKey: trackKey)) }
        if answered.contains(key) { return .done(.notFound) }
        if let f = failures[key] {
            guard Self.retryDelay(afterFailures: f.count) != nil else { return .done(.notFound) }   // opgivet
            let wait = f.nextAllowed.timeIntervalSince(now())
            if wait > 0 { return .retry(after: wait) }
        }
        let entry: LyricsCacheEntry?
        if let task = inFlight[key] {
            entry = await task.value
        } else {
            let task = Task<LyricsCacheEntry?, Never> {
                if let fetcher = self.fetcher { return await fetcher(q) }
                return await self.fetch(q)
            }
            inFlight[key] = task
            entry = await task.value
            inFlight[key] = nil
            if let entry {
                answered.insert(key)
                failures[key] = nil
                cache.store(entry, for: key)
            } else {
                let count = (failures[key]?.count ?? 0) + 1
                let delay = Self.retryDelay(afterFailures: count)
                failures[key] = (count, now().addingTimeInterval(delay ?? 0))
                NowPlayingLog.log("[lyrics] midlertidig fejl nr. \(count) for “\(q.title)” – "
                    + (delay.map { "prøver igen om \(Int($0)) s" } ?? "opgiver i denne kørsel"))
            }
        }
        guard let entry else {
            let f = failures[key]
            guard let f, Self.retryDelay(afterFailures: f.count) != nil else { return .done(.notFound) }
            return .retry(after: max(0, f.nextAllowed.timeIntervalSince(now())))
        }
        return .done(Self.state(from: entry, trackKey: trackKey))
    }

    static func state(from e: LyricsCacheEntry, trackKey: String) -> LyricsState {
        if e.instrumental { return .found(Lyrics(trackKey: trackKey, lines: [], instrumental: true)) }
        guard let synced = e.synced else { return .notFound }
        let lyrics = LRCParser.parse(synced, trackKey: trackKey)
        return lyrics.lines.isEmpty ? .notFound : .found(lyrics)
    }

    /// nil = netværksfejl (prøv ikke at cache det på disk).
    private func fetch(_ q: Query) async -> LyricsCacheEntry? {
        let t0 = Date()
        var attempts: [(String, String)] = [(q.title, q.artist)]
        let cleanTitle = LyricsMatching.cleanTitle(q.title), primary = LyricsMatching.primaryArtist(q.artist)
        if cleanTitle != q.title || primary != q.artist { attempts.append((cleanTitle, primary)) }
        var hadError = false
        for (i, (title, artist)) in attempts.enumerated() {
            let album = i == 0 ? q.album : ""
            switch await get(title: title, artist: artist, album: album, duration: q.duration) {
            case .success(let c?): return log(entry(from: c), q, t0)
            case .success(nil): break
            case .failure: hadError = true
            }
            switch await search(title: title, artist: artist) {
            case .success(let list):
                if let c = LyricsMatching.bestMatch(list, title: q.title, artist: q.artist,
                                                    duration: q.duration > 0 ? q.duration : nil) {
                    return log(entry(from: c), q, t0)
                }
            case .failure: hadError = true
            }
        }
        if hadError { return nil }   // midlertidig fejl: backoff i `lyrics(for:)`
        return log(LyricsCacheEntry(synced: nil, fetched: .now), q, t0)
    }

    private func entry(from c: LyricsMatching.Candidate) -> LyricsCacheEntry {
        LyricsCacheEntry(synced: (c.syncedLyrics ?? "").isEmpty ? nil : c.syncedLyrics, instrumental: c.instrumental, fetched: .now)
    }

    private func log(_ e: LyricsCacheEntry, _ q: Query, _ t0: Date) -> LyricsCacheEntry {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if e.instrumental {
            NowPlayingLog.log("[lyrics] instrumental “\(q.title)” \(ms) ms")
        } else if let s = e.synced {
            let l = LRCParser.parse(s, trackKey: "")
            NowPlayingLog.log("[lyrics] fundet \(l.lines.count) linjer (ord-timing: \(l.lines.contains { !$0.words.isEmpty } ? "ja" : "nej")) "
                + "“\(q.title)” \(ms) ms")
        } else {
            NowPlayingLog.log("[lyrics] ikke fundet “\(q.title)” – \(q.artist) \(ms) ms")
        }
        return e
    }

    private struct Record: Decodable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?

        var candidate: LyricsMatching.Candidate {
            .init(trackName: trackName ?? "", artistName: artistName ?? "", duration: duration,
                  syncedLyrics: syncedLyrics, instrumental: instrumental ?? false)
        }
    }

    /// HTTP-fejl der ikke er 404 og ikke 2xx. Kun 5xx og 429 regnes for midlertidige.
    struct HTTPError: Error { var status: Int }

    /// Midlertidig fejl (prøv igen senere): 5xx, 429, timeout og andre netværksfejl.
    static func isTransient(_ error: Error) -> Bool {
        if let h = error as? HTTPError { return h.status >= 500 || h.status == 429 }
        return true   // URLError (timeout, ingen forbindelse …)
    }

    /// `/api/get`: success(nil) ved 404 eller når der kun er plainLyrics.
    private func get(title: String, artist: String, album: String, duration: TimeInterval) async -> Result<LyricsMatching.Candidate?, Error> {
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        switch await request("get", items) {
        case .failure(let e): return .failure(e)
        case .success(nil): return .success(nil)
        case .success(let data?):
            guard let r = try? JSONDecoder().decode(Record.self, from: data) else { return .success(nil) }
            let c = r.candidate
            return .success(c.instrumental || !(c.syncedLyrics ?? "").isEmpty ? c : nil)
        }
    }

    private func search(title: String, artist: String) async -> Result<[LyricsMatching.Candidate], Error> {
        switch await request("search", [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]) {
        case .failure(let e): return .failure(e)
        case .success(nil): return .success([])
        case .success(let data?):
            return .success(((try? JSONDecoder().decode([Record].self, from: data)) ?? []).map(\.candidate))
        }
    }

    /// success(nil) ved 404.
    private func request(_ endpoint: String, _ items: [URLQueryItem]) async -> Result<Data?, Error> {
        guard var comps = URLComponents(url: Self.baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            return .success(nil)
        }
        comps.queryItems = items
        guard let url = comps.url else { return .success(nil) }
        do {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { return .success(nil) }
            guard (200..<300).contains(code) else {
                let e = HTTPError(status: code)
                NowPlayingLog.log("[lyrics] LRCLIB svarede \(code) på /\(endpoint)")
                // Andre 4xx (fx 400) behandles som "ikke fundet".
                return Self.isTransient(e) ? .failure(e) : .success(nil)
            }
            return .success(data)
        } catch {
            NowPlayingLog.log("[lyrics] netværksfejl på /\(endpoint): \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
