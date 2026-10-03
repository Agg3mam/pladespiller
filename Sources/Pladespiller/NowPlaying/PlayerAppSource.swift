import AppKit

/// Tilstand som en musik-app rapporterer den (fra AppleScript eller en notifikation).
struct PlayerStatus: Equatable, Sendable {
    enum State: Sendable { case playing, paused, stopped }

    var state: State
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0        // sekunder, 0 = ukendt (fx radio)
    var position: TimeInterval?           // sekunder, nil = ukendt
    var trackID = ""                      // Spotify: spotify:track:…, Musik: persistent ID (hex)
    var artworkURL: String?               // Spotify
    var artworkCount: Int?                // Musik

    /// Bruges til at genkende samme sang, også hvis appen ikke giver et id.
    var identity: String { trackID.isEmpty ? "\(title)|\(artist)|\(album)" : trackID }

    static func state(from text: String?) -> State? {
        // Hvis appens ordbog ikke er tilgængelig, kommer konstanten rå: «constant ****kPSP».
        if let t = text {
            if t.contains("kPSP") || t.contains("kPSF") || t.contains("kPSR") { return .playing }
            if t.contains("kPSp") { return .paused }
            if t.contains("kPSS") { return .stopped }
        }
        switch text?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "playing", "fast forwarding", "rewinding": return .playing
        case "paused": return .paused
        case "stopped": return .stopped
        default: return nil
        }
    }
}

/// Resultat af et status-script.
enum StatusResult: Equatable {
    case notRunning
    case status(PlayerStatus)   // state == .stopped betyder "intet spiller"
    case unreadable
}

/// Resultat af at hente et cover.
enum ArtworkResult {
    case image(NSImage)
    case none          // sangen har ikke noget cover
    case notYet        // mangler oplysninger (fx artwork url) — prøv igen ved næste status
}

/// Fælles logik for Spotify og Musik: notifikationer, sikkerhedsnet-tjek, app-start/-luk,
/// AppleScript væk fra main thread, cover og valg af hvornår `onChange` kaldes.
///
/// Underklasser leverer scripts og parsning.
class PlayerAppSource: NowPlayingSource {
    let bundleID: String
    let shortName: String
    private(set) var current: NowPlaying?
    private(set) var lastChange = Date.distantPast
    var onChange: (() -> Void)?

    /// Sikkerhedsnet: tjek så ofte mens der spilles (aldrig ellers).
    var pollInterval: TimeInterval = 5

    // MARK: Til underklasser

    var notificationName: Notification.Name { fatalError("override") }
    var statusScript: String { fatalError("override") }
    func commandScript(_ command: PlayerCommand) -> String { fatalError("override") }
    func parseStatus(_ value: ScriptValue) -> StatusResult { fatalError("override") }
    func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? { nil }
    /// Skal der hentes via AppleScript efter denne notifikation?
    func needsFetch(after notified: PlayerStatus, previous: PlayerStatus?, hasArtwork: Bool) -> Bool { true }
    func loadArtwork(for status: PlayerStatus) async -> ArtworkResult { .none }

    enum PlayerCommand: String { case playPause = "playpause", next, previous }

    // MARK: Tilstand

    private(set) var status: PlayerStatus?
    private var artwork: (id: String, image: NSImage?)?
    private var artworkLoadingID: String?
    private var started = false
    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var notificationGeneration = 0
    private var fetchInFlight = false
    private var fetchPending = false
    private var deniedUntil: Date?

    init(bundleID: String, shortName: String) {
        self.bundleID = bundleID
        self.shortName = shortName
    }

    var isAppRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    func start() {
        guard !started else { return }
        started = true
        let dnc = DistributedNotificationCenter.default()
        let o1 = dnc.addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] note in
            nonisolated(unsafe) let info = note.userInfo   // køen er .main, så den krydser ikke tråde
            MainActor.assumeIsolated { self?.handleNotification(info) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        let o2 = ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { if id == self?.bundleID { self?.appLaunched() } }
        }
        let o3 = ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { if id == self?.bundleID { self?.appTerminated() } }
        }
        observers = [(dnc, o1), (ws, o2), (ws, o3)]
        if isAppRunning {
            NowPlayingLog.log("[\(shortName)] kører ved start – henter status")
            requestFetch(reason: "start")
        } else {
            NowPlayingLog.log("[\(shortName)] kører ikke – venter (sender intet)")
        }
    }

    func stop() {
        started = false
        for (center, o) in observers { center.removeObserver(o) }
        observers = []
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func playPause() { send(.playPause) }
    func nextTrack() { send(.next) }
    func previousTrack() { send(.previous) }

    // MARK: Hændelser

    private func handleNotification(_ info: [AnyHashable: Any]?) {
        notificationGeneration += 1
        let parsed = info.flatMap { parseNotification($0) }
        if let p = parsed {
            NowPlayingLog.log("[\(shortName)] notifikation: \(p.state) “\(p.title)” – \(p.artist)"
                + (p.position.map { String(format: " pos %.1f s", $0) } ?? "")
                + (p.duration > 0 ? String(format: " / %.1f s", p.duration) : ""))
        } else {
            NowPlayingLog.log("[\(shortName)] notifikation (uden brugbar userInfo)")
        }
        guard started else { return }
        guard let p = parsed else { requestFetch(reason: "notifikation"); return }
        let previous = status
        let hasArtwork = artwork?.id == p.identity
        if p.state == .stopped && !isAppRunning {
            apply(nil, measuredAt: .now)
            return
        }
        apply(p, measuredAt: .now)
        if p.state != .stopped, needsFetch(after: p, previous: previous, hasArtwork: hasArtwork) {
            requestFetch(reason: "notifikation", delay: 0.15)
        }
    }

    private func appLaunched() {
        // Intet AppleScript her: appen spiller ikke lige efter start, og notifikationen kommer,
        // når den begynder. Så får brugeren først tilladelsesvinduet, når der faktisk spilles.
        NowPlayingLog.log("[\(shortName)] app startet")
    }

    private func appTerminated() {
        NowPlayingLog.log("[\(shortName)] app lukket")
        fetchPending = false
        apply(nil, measuredAt: .now)
    }

    // MARK: AppleScript

    /// Henter status via AppleScript (aldrig hvis appen ikke kører; højst ét kald ad gangen).
    func requestFetch(reason: String, delay: TimeInterval = 0) {
        guard started, isAppRunning else { return }
        if let until = deniedUntil, until > .now { return }
        if fetchInFlight { fetchPending = true; return }
        fetchInFlight = true
        let generation = notificationGeneration
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            defer {
                self.fetchInFlight = false
                if self.fetchPending { self.fetchPending = false; self.requestFetch(reason: "afventende") }
            }
            guard self.started, self.isAppRunning else { return }
            let outcome = await AppleScriptRunner.shared.run(self.statusScript)
            self.handle(outcome, reason: reason, staleIfNotifiedSince: generation)
        }
    }

    private func handle(_ outcome: ScriptOutcome, reason: String, staleIfNotifiedSince generation: Int) {
        switch outcome.result {
        case .failure(let e):
            if e.isNotAuthorized {
                deniedUntil = Date.now.addingTimeInterval(60)
                NowPlayingLog.log("[\(shortName)] INGEN TILLADELSE til at styre appen (Systemindstillinger › Anonymitet og sikkerhed › Automatisering). Bruger kun notifikationer; prøver igen om 60 s.")
            } else if e.isAppGone {
                NowPlayingLog.log("[\(shortName)] appen forsvandt under kaldet")
            } else {
                NowPlayingLog.log("[\(shortName)] \(e) (\(outcome.milliseconds) ms)")
            }
        case .success(let value):
            deniedUntil = nil
            let parsed = parseStatus(value)
            NowPlayingLog.log("[\(shortName)] AppleScript (\(reason)) \(outcome.milliseconds) ms: \(describe(parsed))")
            guard started else { return }
            switch parsed {
            case .notRunning:
                apply(nil, measuredAt: outcome.measuredAt)
            case .unreadable:
                break
            case .status(let s):
                if generation != notificationGeneration {
                    // En notifikation kom imens; den er nyere. Brug kun ekstra felter (cover-url m.m.).
                    mergeExtras(from: s)
                } else {
                    apply(s, measuredAt: outcome.measuredAt)
                }
            }
        }
    }

    private func describe(_ r: StatusResult) -> String {
        switch r {
        case .notRunning: return "kører ikke"
        case .unreadable: return "kunne ikke læses"
        case .status(let s):
            return "\(s.state) “\(s.title)” – \(s.artist)"
                + (s.position.map { String(format: " pos %.2f s", $0) } ?? "")
                + String(format: " / %.1f s", s.duration)
        }
    }

    private func send(_ command: PlayerCommand) {
        guard isAppRunning else {
            NowPlayingLog.log("[\(shortName)] \(command.rawValue): appen kører ikke – sender intet")
            return
        }
        let script = commandScript(command)
        Task {
            let outcome = await AppleScriptRunner.shared.run(script)
            switch outcome.result {
            case .success: NowPlayingLog.log("[\(self.shortName)] sendt \(command.rawValue) (\(outcome.milliseconds) ms)")
            case .failure(let e): NowPlayingLog.log("[\(self.shortName)] \(command.rawValue) fejlede: \(e)")
            }
            try? await Task.sleep(for: .milliseconds(350))
            self.requestFetch(reason: "efter \(command.rawValue)")
        }
    }

    // MARK: Opdatering af `current`

    /// Anvender en ny status. `onChange` kaldes kun ved reelle ændringer, og `lastChange`
    /// flyttes kun ved ny sang, afspil/pause eller spring i sangen (ikke ved små justeringer
    /// eller når coveret ankommer), så valget mellem to kilder er stabilt.
    func apply(_ incoming: PlayerStatus?, measuredAt: Date) {
        guard var new = incoming, new.state != .stopped else {
            status = nil
            if current != nil { set(nil, significant: true) }
            updatePolling()
            return
        }
        let sameTrack = status?.identity == new.identity
        if sameTrack, let old = status {
            new.artworkURL = new.artworkURL ?? old.artworkURL
            new.artworkCount = new.artworkCount ?? old.artworkCount
            if new.duration <= 0 { new.duration = old.duration }
        }
        let predicted = sameTrack ? current?.position(at: measuredAt) : nil
        let position = new.position ?? predicted ?? 0
        status = new

        let image = artwork?.id == new.identity ? artwork?.image : nil
        let np = NowPlaying(title: new.title, artist: new.artist, album: new.album, artwork: image,
                            duration: new.duration, position: position, positionTimestamp: measuredAt,
                            isPlaying: new.state == .playing, sourceAppBundleID: bundleID)
        if let prev = current {
            let drift = abs(prev.position(at: measuredAt) - np.position(at: measuredAt))
            if prev.trackKey != np.trackKey || prev.isPlaying != np.isPlaying || !sameTrack {
                set(np, significant: true)
            } else if drift > 3 {
                set(np, significant: true)          // spring i sangen
            } else if drift > 0.75 || abs(prev.duration - np.duration) > 0.5 || prev.artwork !== np.artwork {
                set(np, significant: false)         // lille justering
            }
        } else {
            set(np, significant: true)
        }
        ensureArtwork(for: new)
        updatePolling()
    }

    private func mergeExtras(from s: PlayerStatus) {
        guard var st = status, st.identity == s.identity else { return }
        st.artworkURL = st.artworkURL ?? s.artworkURL
        st.artworkCount = st.artworkCount ?? s.artworkCount
        if st.duration <= 0 { st.duration = s.duration }
        status = st
        ensureArtwork(for: st)
    }

    private func set(_ np: NowPlaying?, significant: Bool) {
        current = np
        if significant { lastChange = .now }
        onChange?()
    }

    private func ensureArtwork(for s: PlayerStatus) {
        let id = s.identity
        guard artwork?.id != id, artworkLoadingID != id else { return }
        artworkLoadingID = id
        let t0 = Date()
        Task {
            let result = await self.loadArtwork(for: s)
            if self.artworkLoadingID == id { self.artworkLoadingID = nil }
            guard self.status?.identity == id else { return }
            let image: NSImage?
            switch result {
            case .notYet: return
            case .none: image = nil
            case .image(let i): image = i
            }
            self.artwork = (id, image)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            NowPlayingLog.log("[\(self.shortName)] cover: " + (image.map { "\(Self.pixelSize($0)) (\(ms) ms)" } ?? "intet"))
            if var np = self.current, np.artwork !== image {
                np.artwork = image
                self.set(np, significant: false)
            }
        }
    }

    static func pixelSize(_ image: NSImage) -> String {
        if let rep = image.representations.first, rep.pixelsWide > 0 { return "\(rep.pixelsWide)×\(rep.pixelsHigh) px" }
        return "\(Int(image.size.width))×\(Int(image.size.height)) pt"
    }

    // MARK: Sikkerhedsnet

    private func updatePolling() {
        let shouldPoll = started && current?.isPlaying == true && isAppRunning
        if shouldPoll, pollTimer == nil {
            let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.isAppRunning { self.requestFetch(reason: "tjek") } else { self.appTerminated() }
                }
            }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        } else if !shouldPoll, let t = pollTimer {
            t.invalidate()
            pollTimer = nil
        }
    }
}

// MARK: - Hjælpere til notifikationers userInfo

enum UserInfoValue {
    static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }
}
