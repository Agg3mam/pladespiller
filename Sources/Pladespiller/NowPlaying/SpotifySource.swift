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
        guard let url = status.artworkURL, !url.isEmpty else {
            return status.trackID.isEmpty ? .none : .notYet
        }
        if let image = await covers.load(urlString: url) { return .image(image) }
        return .none
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
