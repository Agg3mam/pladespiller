import AppKit

/// Musik-appen (Apple Music) via AppleScript (NSAppleScript) + `com.apple.Music.playerInfo`.
///
/// Notifikationen har tilstand, navn, kunstner, album, varighed og id, men ikke position.
/// Derfor hentes status via AppleScript efter hver notifikation (ét hurtigt kald), og coveret
/// hentes med et separat script (`raw data of artwork 1`, ellers `data of artwork 1`), kun ved ny sang.
final class MusicSource: PlayerAppSource {
    private let covers = ArtworkCache(capacity: 5)

    init() { super.init(bundleID: NowPlaying.BundleID.music, shortName: "musik") }

    override var notificationName: Notification.Name { Notification.Name("com.apple.Music.playerInfo") }

    static let statusScriptSource = AppleScriptTemplate.guarded(bundleID: NowPlaying.BundleID.music, body: """
        set pState to (player state as text)
        if pState is "stopped" then return {pState}
        set tName to ""
        set tArtist to ""
        set tAlbum to ""
        set tDuration to missing value
        set tPID to ""
        set tArtCount to 0
        set tStream to ""
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
        \t\tset tPID to persistent ID of t
        \tend try
        \ttry
        \t\tset tArtCount to count of artworks of t
        \tend try
        end try
        try
        \tset tStream to current stream title
        end try
        if tStream is missing value then set tStream to ""
        return {pState, tName, tArtist, tAlbum, tDuration, pPos, tPID, tArtCount, tStream}
        """)

    static let artworkScriptSource = AppleScriptTemplate.guarded(bundleID: NowPlaying.BundleID.music, timeout: 5, body: """
        set t to current track
        set tPID to persistent ID of t
        if (count of artworks of t) is 0 then return {tPID, missing value}
        try
        \treturn {tPID, raw data of artwork 1 of t}
        on error
        \treturn {tPID, data of artwork 1 of t}
        end try
        """, otherwise: "return {\"notrunning\", missing value}")

    override var statusScript: String { Self.statusScriptSource }

    override func commandScript(_ command: PlayerCommand) -> String {
        // "back track" = som Musik-appens egen knap: til start af sangen, eller forrige hvis allerede ved start.
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "back track"
        }
        return AppleScriptTemplate.guarded(bundleID: bundleID, body: verb, otherwise: "")
    }

    override func parseStatus(_ value: ScriptValue) -> StatusResult { Self.parseStatus(value) }
    override func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? { Self.parseNotification(info) }

    // Position mangler altid i notifikationen → hent.
    override func needsFetch(after notified: PlayerStatus, previous: PlayerStatus?, hasArtwork: Bool) -> Bool { true }

    override func loadArtwork(for status: PlayerStatus) async -> ArtworkResult {
        guard !status.trackID.isEmpty else { return status.artworkCount == nil ? .notYet : .none }
        if let cached = covers.image(for: status.trackID) { return .image(cached) }
        guard let count = status.artworkCount else { return .notYet }   // vent på AppleScript-status
        guard count > 0, isAppRunning else { return .none }
        let outcome = await AppleScriptRunner.shared.run(Self.artworkScriptSource)
        guard case .success(let v) = outcome.result else {
            if case .failure(let e) = outcome.result { NowPlayingLog.log("[musik] cover fejlede: \(e)") }
            return .none
        }
        guard let (pid, data) = Self.parseArtwork(v), pid == status.trackID else { return .notYet }
        guard let data, let image = NSImage(data: data) else { return .none }
        covers.insert(image, for: pid)
        return .image(image)
    }

    // MARK: Ren parsning (testes i --selftest)

    /// `{state, name, artist, album, duration(s)|missing, position(s)|missing, persistent ID, artwork-antal, stream-titel}`.
    static func parseStatus(_ v: ScriptValue) -> StatusResult {
        let first = v[0].string
        if first == "notrunning" { return .notRunning }
        guard let state = PlayerStatus.state(from: first) else { return .unreadable }
        if state == .stopped { return .status(PlayerStatus(state: .stopped)) }
        var s = PlayerStatus(state: state)
        s.title = v[1].string ?? ""
        s.artist = v[2].string ?? ""
        s.album = v[3].string ?? ""
        s.duration = max(0, v[4].double ?? 0)
        s.position = v[5].double.map { max(0, $0) }
        s.trackID = v[6].string ?? ""
        s.artworkCount = v[7].double.map { Int($0) } ?? 0
        let stream = v[8].string ?? ""
        if !stream.isEmpty { applyStreamTitle(stream, to: &s) }
        return .status(s)
    }

    /// Radio/stream: "Kunstner - Titel" i `current stream title`; stationens navn bliver album.
    static func applyStreamTitle(_ stream: String, to s: inout PlayerStatus) {
        let station = s.title
        if let r = stream.range(of: " - ") {
            s.artist = String(stream[..<r.lowerBound])
            s.title = String(stream[r.upperBound...])
        } else {
            s.title = stream
            if s.artist.isEmpty { s.artist = station }
        }
        if s.album.isEmpty { s.album = station }
        // Samme station, ny sang → nyt id, så cover/position nulstilles korrekt.
        s.trackID = s.trackID.isEmpty ? stream : "\(s.trackID)|\(stream)"
    }

    /// `{pid, data|missing}` → (pid, data). nil hvis appen ikke kører / svaret ikke kan læses.
    static func parseArtwork(_ v: ScriptValue) -> (String, Data?)? {
        guard let pid = v[0].string, pid != "notrunning" else { return nil }
        if case .data(let d) = v[1], !d.isEmpty { return (pid, d) }
        return (pid, nil)
    }

    /// userInfo fra `com.apple.Music.playerInfo`: "Player State", "Name", "Artist", "Album",
    /// "Total Time" (ms), "PersistentID" (tal; laves om til samme hex-streng som AppleScript giver).
    static func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? {
        guard let state = PlayerStatus.state(from: UserInfoValue.string(info["Player State"])) else { return nil }
        var s = PlayerStatus(state: state)
        guard state != .stopped else { return s }
        s.title = UserInfoValue.string(info["Name"]) ?? UserInfoValue.string(info["Display Line 0"]) ?? ""
        s.artist = UserInfoValue.string(info["Artist"]) ?? ""
        s.album = UserInfoValue.string(info["Album"]) ?? ""
        s.duration = max(0, (UserInfoValue.double(info["Total Time"]) ?? 0) / 1000)
        s.trackID = persistentIDHex(info["PersistentID"] ?? info["Persistent ID"]) ?? ""
        if let stream = UserInfoValue.string(info["Stream Title"]), !stream.isEmpty {
            applyStreamTitle(stream, to: &s)
        }
        return s
    }

    /// Persistent ID som 16 store hex-cifre (AppleScripts format). Tal kan være negative (signed 64-bit).
    static func persistentIDHex(_ v: Any?) -> String? {
        switch v {
        case let n as NSNumber: return String(format: "%016llX", UInt64(bitPattern: n.int64Value))
        case let s as String where !s.isEmpty:
            if let i = Int64(s) { return String(format: "%016llX", UInt64(bitPattern: i)) }
            return s.uppercased()
        default: return nil
        }
    }
}
