import AppKit

/// Spotify via pid-adresserede Apple Events (reserve: AppleScript) + `com.spotify.client.PlaybackStateChanged`.
///
/// Notifikationen indeholder næsten alt (tilstand, navn, kunstner, album, varighed, position, id),
/// så Apple Events bruges kun ved ny sang (for at få artwork url), når position mangler,
/// efter knaptryk og som sikkerhedsnet hvert 5. sekund mens der spilles.
///
/// Koder fra Spotify.sdef: player state pPlS, player position pPos, current track pTrk,
/// name pnam, artist pArt, album pAlb, duration pDur (ms), artwork url aUrl, id "ID  ";
/// playpause spfy/PlPs, next track spfy/Next, previous track spfy/Prev.
final class SpotifySource: PlayerAppSource {
    private let covers = ArtworkCache(capacity: 5)

    init() { super.init(bundleID: NowPlaying.BundleID.spotify, shortName: "spotify", displayName: "Spotify") }

    override var notificationName: Notification.Name { Notification.Name("com.spotify.client.PlaybackStateChanged") }

    static let statusScriptSource = AppleScriptTemplate.guarded(bundleID: NowPlaying.BundleID.spotify, body: """
        set pState to (player state as text)
        if pState is "stopped" then return {pState}
        set tName to ""
        set tArtist to ""
        set tAlbum to ""
        set tDuration to 0
        set tArtURL to ""
        set tID to ""
        set pPos to missing value
        try
        \tset pPos to player position
        end try
        try
        \tset t to current track
        \ttry
        \t\tset tName to name of t
        \tend try
        \ttry
        \t\tset tArtist to artist of t
        \tend try
        \ttry
        \t\tset tAlbum to album of t
        \tend try
        \ttry
        \t\tset tDuration to duration of t
        \tend try
        \ttry
        \t\tset tArtURL to artwork url of t
        \tend try
        \ttry
        \t\tset tID to id of t
        \tend try
        end try
        return {pState, tName, tArtist, tAlbum, tDuration, pPos, tArtURL, tID}
        """)

    override var statusScript: String { Self.statusScriptSource }

    override var statusFetch: @Sendable (AETarget) throws(ScriptError) -> ScriptValue { Self.fetchStatus }

    /// Samme liste som status-scriptet: `{state, name, artist, album, duration(ms), position, artwork url, id}`.
    nonisolated static func fetchStatus(_ t: AETarget) throws(ScriptError) -> ScriptValue {
        let state = try t.get(AE.prop("pPlS"))
        if PlayerStatus.state(from: state.string) == .stopped { return .list([.text("stopped")]) }
        let track = AE.prop("pTrk")
        let position = try t.get(AE.prop("pPos"), or: .missing)
        return .list([
            state,
            try t.get(AE.prop("pnam", of: track), or: .text("")),
            try t.get(AE.prop("pArt", of: track), or: .text("")),
            try t.get(AE.prop("pAlb", of: track), or: .text("")),
            try t.get(AE.prop("pDur", of: track), or: .number(0)),
            position,
            try t.get(AE.prop("aUrl", of: track), or: .text("")),
            try t.get(AE.prop("ID  ", of: track), or: .text("")),
        ])
    }

    override func commandEvent(_ command: PlayerCommand) -> (String, String) {
        switch command {
        case .playPause: ("spfy", "PlPs")
        case .next: ("spfy", "Next")
        case .previous: ("spfy", "Prev")
        }
    }

    override func commandScript(_ command: PlayerCommand) -> String {
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return AppleScriptTemplate.guarded(bundleID: bundleID, body: verb, otherwise: "")
    }

    override func parseStatus(_ value: ScriptValue) -> StatusResult { Self.parseStatus(value) }
    override func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? { Self.parseNotification(info) }

    override func needsFetch(after notified: PlayerStatus, previous: PlayerStatus?, hasArtwork: Bool) -> Bool {
        if notified.position == nil { return true }
        // Ny sang uden kendt cover-url → hent artwork url.
        return !hasArtwork && notified.artworkURL == nil
    }

    override func loadArtwork(for status: PlayerStatus) async -> ArtworkResult {
        if let url = status.artworkURL, !url.isEmpty {
            if let image = await covers.load(urlString: url) { return .image(image) }
        }
        // Spotifys AppleScript giver ikke altid en cover-url (fejl -1728 på nyere macOS og ved Spotify Connect).
        // Så slår vi coveret op hos Spotify selv ud fra sangens id (brugeren har sagt ja: kun id'et sendes).
        guard !status.trackID.isEmpty else { return .none }
        if let url = await oEmbedCoverURL(trackID: status.trackID),
           let image = await covers.load(urlString: url) { return .image(image) }
        return .none
    }

    // MARK: Cover via Spotifys oEmbed (uden AppleScript)

    /// Opslag pr. sang-id → cover-url (husker også "ingen", så samme sang aldrig slås op to gange i en kørsel).
    private var oEmbedCache: [String: String?] = [:]
    private let oEmbedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    private func oEmbedCoverURL(trackID: String) async -> String? {
        if let hit = oEmbedCache[trackID] { return hit }
        guard let url = Self.oEmbedRequestURL(trackID: trackID) else { return nil }
        let t0 = Date()
        var result: String?
        do {
            let (data, response) = try await oEmbedSession.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                NowPlayingLog.log("[spotify] cover-opslag: HTTP \(http.statusCode)")
            } else {
                result = Self.parseOEmbedThumbnail(data).map(Self.largeCoverURL)
            }
        } catch {
            NowPlayingLog.log("[spotify] cover-opslag fejlede: \(error.localizedDescription)")
        }
        NowPlayingLog.log("[spotify] cover-opslag \(Int(Date().timeIntervalSince(t0) * 1000)) ms: " + (result ?? "intet"))
        oEmbedCache[trackID] = result
        return result
    }

    /// `spotify:track:ID` (eller episode) → `https://open.spotify.com/oembed?url=https://open.spotify.com/track/ID`.
    /// Lokale filer (`spotify:local:…`) har intet cover hos Spotify.
    nonisolated static func oEmbedRequestURL(trackID: String) -> URL? {
        let parts = trackID.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", ["track", "episode"].contains(String(parts[1])),
              parts[2].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        var c = URLComponents(string: "https://open.spotify.com/oembed")
        c?.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/\(parts[1])/\(parts[2])")]
        return c?.url
    }

    nonisolated static func parseOEmbedThumbnail(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumb = json["thumbnail_url"] as? String, thumb.hasPrefix("https://") else { return nil }
        return thumb
    }

    /// oEmbed giver 300 px; samme billede findes i 640 px (Spotifys billed-id med en anden størrelseskode).
    nonisolated static func largeCoverURL(_ thumb: String) -> String {
        thumb.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273")
    }

    // MARK: Ren parsning (testes i --selftest)

    /// `{state, name, artist, album, duration(ms), position(s), artwork url, id}` eller `{"stopped"}` / `{"notrunning"}`.
    static func parseStatus(_ v: ScriptValue) -> StatusResult {
        let first = v[0].string
        if first == "notrunning" { return .notRunning }
        guard let state = PlayerStatus.state(from: first) else { return .unreadable }
        if state == .stopped { return .status(PlayerStatus(state: .stopped)) }
        var s = PlayerStatus(state: state)
        s.title = v[1].string ?? ""
        s.artist = v[2].string ?? ""
        s.album = v[3].string ?? ""
        s.duration = max(0, (v[4].double ?? 0) / 1000)       // ms → s
        s.position = v[5].double.map { max(0, $0) }
        let url = v[6].string ?? ""
        s.artworkURL = url.isEmpty ? nil : url
        s.trackID = v[7].string ?? ""
        return .status(s)
    }

    /// userInfo fra `com.spotify.client.PlaybackStateChanged`:
    /// "Player State" (Playing/Paused/Stopped), "Name", "Artist", "Album", "Duration" (ms),
    /// "Playback Position" (s), "Track ID".
    static func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? {
        guard let state = PlayerStatus.state(from: UserInfoValue.string(info["Player State"])) else { return nil }
        var s = PlayerStatus(state: state)
        guard state != .stopped else { return s }
        s.title = UserInfoValue.string(info["Name"]) ?? ""
        s.artist = UserInfoValue.string(info["Artist"]) ?? ""
        s.album = UserInfoValue.string(info["Album"]) ?? ""
        s.duration = max(0, (UserInfoValue.double(info["Duration"]) ?? 0) / 1000)
        s.position = UserInfoValue.double(info["Playback Position"]).map { max(0, $0) }
        s.trackID = UserInfoValue.string(info["Track ID"]) ?? ""
        return s
    }
}
