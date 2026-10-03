import AppKit

/// Musik-appen (Apple Music) via pid-adresserede Apple Events (reserve: AppleScript) + `com.apple.Music.playerInfo`.
///
/// Notifikationen har tilstand, navn, kunstner, album, varighed og id, men ikke position.
/// Derfor hentes status efter hver notifikation, og coveret hentes separat
/// (`raw data of artwork 1`, ellers `data of artwork 1`), kun én gang pr. sang/station.
///
/// Koder fra com.apple.Music.sdef: pPlS, pPos, pTrk, pnam, pArt, pAlb, pDur (s), persistent ID pPIS,
/// current stream title pStT, artwork cArt (raw data pRaw, data pPCT);
/// playpause hook/PlPs, next track hook/Next, back track hook/Back.
final class MusicSource: PlayerAppSource {
    private let covers = ArtworkCache(capacity: 5)
    /// Persistent ID'er der ikke har et cover (så der ikke spørges igen, fx ved hver ny sang på en radiostation).
    private var withoutArtwork: [String] = []

    init() { super.init(bundleID: NowPlaying.BundleID.music, shortName: "musik", displayName: "Musik") }

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

    override var statusFetch: @Sendable (AETarget) throws(ScriptError) -> ScriptValue { Self.fetchStatus }

    /// Samme liste som status-scriptet: `{state, name, artist, album, duration, position, pid, artwork-antal, stream-titel}`.
    nonisolated static func fetchStatus(_ t: AETarget) throws(ScriptError) -> ScriptValue {
        let state = try t.get(AE.prop("pPlS"))
        if PlayerStatus.state(from: state.string) == .stopped { return .list([.text("stopped")]) }
        let track = AE.prop("pTrk")
        let position = try t.get(AE.prop("pPos"), or: .missing)
        let stream = try t.get(AE.prop("pStT"), or: .missing)
        return .list([
            state,
            try t.get(AE.prop("pnam", of: track), or: .text("")),
            try t.get(AE.prop("pArt", of: track), or: .text("")),
            try t.get(AE.prop("pAlb", of: track), or: .text("")),
            try t.get(AE.prop("pDur", of: track), or: .missing),
            position,
            try t.get(AE.prop("pPIS", of: track), or: .text("")),
            .number(Double(try artworkCount(t, track))),
            stream.string == nil ? .text("") : stream,
        ])
    }

    /// `{pid, data|missing}`.
    nonisolated static func fetchArtwork(_ t: AETarget) throws(ScriptError) -> ScriptValue {
        var t = t
        t.timeout = 5
        let track = AE.prop("pTrk")
        let pid = try t.get(AE.prop("pPIS", of: track), or: .missing)
        guard try artworkCount(t, track) > 0 else { return .list([pid, .missing]) }
        let art = AE.element("cArt", 1, of: track)
        if case .data(let d) = try t.get(AE.prop("pRaw", of: art), or: .missing), !d.isEmpty {
            return .list([pid, .data(d)])
        }
        return .list([pid, try t.get(AE.prop("pPCT", of: art), or: .missing)])
    }

    private nonisolated static func artworkCount(_ t: AETarget, _ track: NSAppleEventDescriptor) throws(ScriptError) -> Int {
        do { return try t.count("cArt", in: track) } catch {
            if error.isNotAuthorized || error.isAppGone || error.isTimeout || error.needsConsent { throw error }
            return 0
        }
    }

    override func commandEvent(_ command: PlayerCommand) -> (String, String) {
        switch command {
        case .playPause: ("hook", "PlPs")
        case .next: ("hook", "Next")
        case .previous: ("hook", "Back")    // som Musiks egen knap (brugerens valg)
        }
    }

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
        let pid = Self.basePersistentID(status.trackID)
        guard !pid.isEmpty else { return status.artworkCount == nil ? .notYet : .none }
        if let cached = covers.image(for: pid) { return .image(cached) }
        if withoutArtwork.contains(pid) { return .none }
        guard let count = status.artworkCount else { return .notYet }   // vent på status (antal covers)
        guard count > 0 else { rememberNoArtwork(pid); return .none }
        let outcome: Timed<ScriptValue>
        if Self.useAppleScript {
            outcome = await AppleScriptRunner.shared.run(Self.artworkScriptSource)
        } else {
            guard let p = runningPID else { return .none }
            outcome = await AppleEventQueue.shared.run(pid: p, Self.fetchArtwork)
        }
        guard case .success(let v) = outcome.result else {
            if case .failure(let e) = outcome.result { NowPlayingLog.log("[musik] cover fejlede: \(e)") }
            return .none
        }
        switch Self.artworkAnswer(v, for: status.trackID) {
        case .otherTrack:
            // Sangen skiftede imens; den nye status henter sit eget cover.
            return .none
        case .noArtwork:
            rememberNoArtwork(pid)
            return .none
        case .data(let data):
            guard let image = NSImage(data: data) else { rememberNoArtwork(pid); return .none }
            covers.insert(image, for: pid)
            return .image(image)
        }
    }

    private func rememberNoArtwork(_ pid: String) {
        withoutArtwork.removeAll { $0 == pid }
        withoutArtwork.append(pid)
        if withoutArtwork.count > 20 { withoutArtwork.removeFirst() }
    }

    enum ArtworkAnswer: Equatable { case data(Data), noArtwork, otherTrack }

    /// Vurderer cover-svaret `{pid, data|missing}` for sangen `trackID`. Radio/streams har
    /// trackID "pid|stream-titel", så der sammenlignes med persistent ID før "|".
    static func artworkAnswer(_ v: ScriptValue, for trackID: String) -> ArtworkAnswer {
        guard let (pid, data) = parseArtwork(v) else { return .noArtwork }
        if !pid.isEmpty, pid != basePersistentID(trackID) { return .otherTrack }
        return data.map { .data($0) } ?? .noArtwork
    }

    /// Persistent ID uden en eventuel "|stream-titel".
    static func basePersistentID(_ trackID: String) -> String {
        trackID.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trackID
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

    /// `{pid, data|missing}` → (pid, data). Ukendt pid giver "". nil hvis appen ikke kører.
    static func parseArtwork(_ v: ScriptValue) -> (String, Data?)? {
        let pid = v[0].string ?? ""
        guard pid != "notrunning" else { return nil }
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
