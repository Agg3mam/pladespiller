import AppKit

/// Tilstand som en musik-app rapporterer den (fra Apple Events eller en notifikation).
nonisolated struct PlayerStatus: Equatable, Sendable {
    enum State: Sendable { case playing, paused, stopped }

    var state: State
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0        // sekunder, 0 = ukendt (fx radio)
    var position: TimeInterval?           // sekunder, nil = ukendt
    var trackID = ""                      // Spotify: spotify:track:…, Musik: persistent ID (hex) [+ "|stream-titel"]
    var artworkURL: String?               // Spotify
    var artworkCount: Int?                // Musik

    /// Bruges til at genkende samme sang, også hvis appen ikke giver et id.
    var identity: String { trackID.isEmpty ? "\(title)|\(artist)|\(album)" : trackID }

    static func state(from text: String?) -> State? {
        // Apple Events giver rå koder (kPSP = playing, kPSp = paused, kPSS = stopped, kPSF/kPSR = spol);
        // AppleScript kan give «constant ****kPSP».
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

/// Resultat af en statusforespørgsel.
enum StatusResult: Equatable {
    case notRunning
    case status(PlayerStatus)   // state == .stopped betyder "intet spiller"
    case unreadable
}

/// Resultat af at hente et cover.
enum ArtworkResult {
    case image(NSImage)
    case none          // sangen har ikke noget cover (huskes, så der ikke spørges igen)
    case notYet        // mangler oplysninger (fx artwork url) — prøv igen ved næste status
}

/// Fælles logik for Spotify og Musik: notifikationer, sikkerhedsnet-tjek, app-start/-luk,
/// tilladelse (TCC), Apple Events væk fra main thread, cover og hvornår `onChange` kaldes.
///
/// Underklasser leverer Apple Events (og AppleScript-reserven) og parsning.
class PlayerAppSource: NowPlayingSource, AccessReporting {
    let bundleID: String
    let shortName: String
    let displayName: String
    private(set) var current: NowPlaying?
    private(set) var lastChange = Date.distantPast
    var onChange: (() -> Void)?

    /// Sat når macOS ikke (endnu) tillader os at styre appen. Kun mens appen kører.
    private(set) var accessProblem: SourceAccessProblem?

    /// Sikkerhedsnet: tjek så ofte mens der spilles (aldrig ellers).
    var pollInterval: TimeInterval = 5

    /// Reserve: brug NSAppleScript i stedet for pid-adresserede Apple Events.
    static let useAppleScript = CommandLine.arguments.contains("--applescript")
        || ProcessInfo.processInfo.environment["PLADESPILLER_APPLESCRIPT"] == "1"

    // MARK: Til underklasser

    var notificationName: Notification.Name { fatalError("override") }
    /// Henter status som en liste (samme form som AppleScript-reserven, så parseren er fælles). Kører på køen.
    var statusFetch: @Sendable (AETarget) throws(ScriptError) -> ScriptValue { fatalError("override") }
    var statusScript: String { fatalError("override") }
    /// (event-klasse, event-id) for en kommando, fx ("spfy", "PlPs").
    func commandEvent(_ command: PlayerCommand) -> (String, String) { fatalError("override") }
    func commandScript(_ command: PlayerCommand) -> String { fatalError("override") }
    func parseStatus(_ value: ScriptValue) -> StatusResult { fatalError("override") }
    func parseNotification(_ info: [AnyHashable: Any]) -> PlayerStatus? { nil }
    /// Skal der hentes status efter denne notifikation?
    func needsFetch(after notified: PlayerStatus, previous: PlayerStatus?, hasArtwork: Bool) -> Bool { true }
    func loadArtwork(for status: PlayerStatus) async -> ArtworkResult { .none }

    enum PlayerCommand: String { case playPause = "playpause", next, previous }

    // MARK: Tilstand

    private(set) var status: PlayerStatus?
    private var artwork: (id: String, image: NSImage?)?
    private var artworkLoadingID: String?
    private var started = false
    private var pollTimer: Timer?
    private var accessTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: DistributedObserver?
    /// Tælles op ved hver notifikation og kommando; et statussvar der blev startet før, er forældet.
    private var stateGeneration = 0
    private var fetchInFlight = false
    private var fetchPending = false
    private var access: AccessState?
    /// Egen seriel kø til denne apps Apple Events (QA N6).
    let events: AppleEventQueue

    init(bundleID: String, shortName: String, displayName: String) {
        self.bundleID = bundleID
        self.shortName = shortName
        self.displayName = displayName
        events = AppleEventQueue(label: shortName)
    }

    var runningPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }?.processIdentifier
    }

    var isAppRunning: Bool { runningPID != nil }

    func start() {
        guard !started else { return }
        started = true
        // `.deliverImmediately`: appen er aldrig aktiv (LSUIElement + ikke-aktiverende panel), og
        // NSApplication suspenderer distribuerede notifikationer for inaktive apps.
        distributedObserver = DistributedObserver(name: notificationName) { [weak self] info in
            self?.handleNotification(info)
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
        workspaceObservers = [o2, o3]
        if isAppRunning {
            NowPlayingLog.log("[\(shortName)] kører ved start – henter status")
            requestFetch(reason: "start")
        } else {
            NowPlayingLog.log("[\(shortName)] kører ikke – venter (sender intet)")
        }
    }

    func stop() {
        started = false
        distributedObserver = nil
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
        accessTimer?.invalidate()
        accessTimer = nil
    }

    func playPause() { send(.playPause) }

    // MARK: Spoling

    /// Højst ét spole-event pr. så mange sekunder mens der trækkes; det sidste sendes altid.
    var seekInterval: TimeInterval = 0.1
    private var pendingSeek: TimeInterval?
    private var seekLoopRunning = false
    private var lastSeekSentAt = Date.distantPast

    /// Klemmer til [0, varighed]. nil når der ikke kan spoles (ukendt varighed, fx radio).
    static func clampSeek(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard duration > 0, position.isFinite else { return nil }
        return min(max(0, position), duration)
    }

    func seek(to position: TimeInterval) {
        guard let np = current, let target = Self.clampSeek(position, duration: np.duration) else { return }
        applyOptimisticSeek(target)
        pendingSeek = target
        runSeekLoop()
    }

    /// Optimistisk: armen/stregen springer med det samme. Statussvar startet før er forældede.
    func applyOptimisticSeek(_ target: TimeInterval, at date: Date = .now) {
        stateGeneration += 1
        guard var np = current else { return }
        np.position = target
        np.positionTimestamp = date
        set(np, significant: true)
        if var s = status { s.position = target; status = s }
    }

    /// Sender ventende spolinger: højst én pr. `seekInterval`, altid den nyeste, og bekræfter bagefter.
    private func runSeekLoop() {
        guard !seekLoopRunning else { return }
        seekLoopRunning = true
        Task {
            while self.pendingSeek != nil {
                let wait = self.seekInterval - Date().timeIntervalSince(self.lastSeekSentAt)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard let target = self.pendingSeek else { break }
                self.pendingSeek = nil
                self.lastSeekSentAt = Date()
                await self.performSeek(target)
                self.stateGeneration += 1     // statussvar startet under afsendelsen er også forældede
            }
            self.seekLoopRunning = false
            // Bekræft (Musik sender ingen notifikation ved spoling).
            try? await Task.sleep(for: .milliseconds(200))
            if self.pendingSeek == nil, !self.seekLoopRunning { self.requestFetch(reason: "efter spoling") }
        }
    }

    /// Sender selve spolingen til appen. (Overskrives i selvtesten.)
    func performSeek(_ target: TimeInterval) async {
        guard let pid = runningPID else { return }
        if access == .denied { NowPlayingLog.log("[\(shortName)] spol: ingen tilladelse – sender intet"); return }
        guard await ensureAccess() else { return }
        let outcome: Timed<ScriptValue>
        if Self.useAppleScript {
            outcome = await AppleScriptRunner.shared.run(AppleScriptTemplate.guarded(
                bundleID: bundleID, body: "set player position to \(String(format: "%.3f", target))", otherwise: ""))
        } else {
            outcome = await events.run(pid: pid) { t throws(ScriptError) in try t.setPlayerPosition(target); return ScriptValue.missing }
        }
        switch outcome.result {
        case .success: NowPlayingLog.log("[\(shortName)] spolet til \(String(format: "%.1f", target)) s (\(outcome.milliseconds) ms)")
        case .failure(let e):
            NowPlayingLog.log("[\(shortName)] spol fejlede: \(e)")
            if e.isNotAuthorized { handleAccess(.denied) }
        }
    }
    func nextTrack() { send(.next) }
    func previousTrack() { send(.previous) }

    // MARK: Hændelser

    private func handleNotification(_ info: [AnyHashable: Any]?) {
        stateGeneration += 1
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
            requestFetch(reason: "notifikation", delay: 0.1)
        }
    }

    private func appLaunched() {
        // Intet Apple Event her: appen spiller ikke lige efter start, og notifikationen kommer,
        // når den begynder.
        NowPlayingLog.log("[\(shortName)] app startet")
    }

    private func appTerminated() {
        NowPlayingLog.log("[\(shortName)] app lukket")
        fetchPending = false
        access = nil
        accessTimer?.invalidate()
        accessTimer = nil
        setAccessProblem(nil)
        apply(nil, measuredAt: .now)
    }

    // MARK: Tilladelse (TCC)

    /// Tjekker/indhenter tilladelse før første kald. Returnerer true, hvis der må sendes.
    private func ensureAccess() async -> Bool {
        if Self.useAppleScript || access == .granted { return true }
        guard let pid = runningPID else { return false }
        var state = await AppleEventQueue.permission(pid: pid, ask: false)
        if state == .notDetermined {
            NowPlayingLog.log("[\(shortName)] tilladelse: ikke spurgt endnu – macOS viser nu vinduet "
                + "“Pladespiller vil styre \(displayName)”")
            setAccessProblem(Self.askingMessage(displayName))
            state = await AppleEventQueue.permission(pid: pid, ask: true)
        }
        return handleAccess(state)
    }

    @discardableResult
    private func handleAccess(_ state: AccessState) -> Bool {
        let changed = access != state
        access = state
        switch state {
        case .granted:
            if changed { NowPlayingLog.log("[\(shortName)] tilladelse: givet") }
            accessTimer?.invalidate()
            accessTimer = nil
            setAccessProblem(nil)
            return true
        case .denied:
            if changed {
                NowPlayingLog.log("[\(shortName)] tilladelse: AFVIST – giv Pladespiller adgang til \(displayName) i "
                    + "Systemindstillinger ▸ Anonymitet og sikkerhed ▸ Automatisering. Bruger kun notifikationer; "
                    + "tjekker igen hvert 10. s (uden vindue)")
            }
            setAccessProblem(Self.deniedMessage(displayName))
            startAccessTimer()
            return false
        case .notDetermined:
            setAccessProblem(Self.askingMessage(displayName))
            startAccessTimer()
            return false
        case .notRunning:
            return false
        case .unknown(let code):
            NowPlayingLog.log("[\(shortName)] tilladelse: ukendt svar \(code) – prøver alligevel")
            access = nil
            return true
        }
    }

    /// Mens adgangen mangler: spørg TCC (uden vindue) hvert 10. s, så beskeden forsvinder,
    /// når brugeren har givet lov i Systemindstillinger.
    private func startAccessTimer() {
        guard accessTimer == nil else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pid = self.runningPID else { return }
                Task {
                    if await AppleEventQueue.permission(pid: pid, ask: false) == .granted {
                        self.handleAccess(.granted)
                        self.requestFetch(reason: "adgang givet")
                    }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        accessTimer = t
    }

    /// Korte tekster til widgetten (højst 2 korte linjer i Lille); den lange forklaring står i loggen (QA N7).
    static func askingMessage(_ app: String) -> String { L("Tillad adgang til \(app)", "Allow access to \(app)") }
    static func deniedMessage(_ app: String) -> String { L("Ingen adgang til \(app) · Åbn Indstillinger", "No access to \(app) · Open Settings") }

    private func setAccessProblem(_ message: String?) {
        let p = message.map { SourceAccessProblem(bundleID: bundleID, message: $0) }
        guard p != accessProblem else { return }
        accessProblem = p
        onChange?()
    }

    // MARK: Status

    /// Henter status (aldrig hvis appen ikke kører; højst ét kald ad gangen).
    func requestFetch(reason: String, delay: TimeInterval = 0) {
        guard started, isAppRunning else { return }
        if fetchInFlight { fetchPending = true; return }
        fetchInFlight = true
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            defer {
                self.fetchInFlight = false
                if self.fetchPending { self.fetchPending = false; self.requestFetch(reason: "afventende") }
            }
            guard self.started, await self.ensureAccess() else { return }
            let generation = self.stateGeneration
            guard let outcome = await self.runStatus() else { return }
            self.handle(outcome, reason: reason, staleIfChangedSince: generation)
        }
    }

    private func runStatus() async -> Timed<ScriptValue>? {
        if Self.useAppleScript { return await AppleScriptRunner.shared.run(statusScript) }
        guard let pid = runningPID else { return nil }
        return await events.run(pid: pid, statusFetch)
    }

    private func handle(_ outcome: Timed<ScriptValue>, reason: String, staleIfChangedSince generation: Int) {
        switch outcome.result {
        case .failure(let e):
            if e.isNotAuthorized {
                handleAccess(.denied)
            } else if e.needsConsent {
                handleAccess(.notDetermined)
            } else if e.isAppGone {
                NowPlayingLog.log("[\(shortName)] appen forsvandt under kaldet")
            } else {
                NowPlayingLog.log("[\(shortName)] \(e) (\(outcome.milliseconds) ms)")
            }
        case .success(let value):
            if Self.useAppleScript { handleAccess(.granted) }
            let parsed = parseStatus(value)
            NowPlayingLog.log("[\(shortName)] status (\(reason)) \(outcome.milliseconds) ms: \(describe(parsed))")
            guard started else { return }
            switch parsed {
            case .notRunning:
                apply(nil, measuredAt: outcome.measuredAt)
            case .unreadable:
                break
            case .status(let s):
                if generation != stateGeneration {
                    // En notifikation/kommando kom imens; den er nyere. Brug kun ekstra felter (cover-url m.m.).
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

    // MARK: Kommandoer

    private func send(_ command: PlayerCommand) {
        guard let pid = runningPID else {
            NowPlayingLog.log("[\(shortName)] \(command.rawValue): appen kører ikke – sender intet")
            return
        }
        if access == .denied {
            NowPlayingLog.log("[\(shortName)] \(command.rawValue): ingen tilladelse – sender intet")
            return
        }
        stateGeneration += 1
        if command == .playPause { applyOptimisticToggle() }
        let (cls, id) = commandEvent(command)
        let script = commandScript(command)
        Task {
            guard await self.ensureAccess() else { return }
            let outcome: Timed<ScriptValue>
            if Self.useAppleScript {
                outcome = await AppleScriptRunner.shared.run(script)
            } else {
                outcome = await self.events.run(pid: pid) { t throws(ScriptError) in try t.send(cls, id) }
            }
            switch outcome.result {
            case .success: NowPlayingLog.log("[\(self.shortName)] sendt \(command.rawValue) (\(outcome.milliseconds) ms)")
            case .failure(let e):
                NowPlayingLog.log("[\(self.shortName)] \(command.rawValue) fejlede: \(e)")
                if e.isNotAuthorized { self.handleAccess(.denied) }
            }
            // Bekræft hurtigt (notifikationen kommer som regel endnu før).
            try? await Task.sleep(for: .milliseconds(150))
            self.requestFetch(reason: "efter \(command.rawValue)")
        }
    }

    /// Optimistisk: vis afspil/pause med det samme; rettes af notifikationen/statussvaret.
    func applyOptimisticToggle(at date: Date = .now) {
        guard var np = current else { return }
        np.position = np.position(at: date)
        np.positionTimestamp = date
        np.isPlaying.toggle()
        set(np, significant: true)
        if var s = status { s.state = np.isPlaying ? .playing : .paused; s.position = np.position; status = s }
        updatePolling()
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

    /// Antal gange et cover er forsøgt hentet (til selvtesten: samme sang må kun spørges én gang).
    private(set) var artworkRequests = 0

    private func ensureArtwork(for s: PlayerStatus) {
        let id = s.identity
        guard artwork?.id != id, artworkLoadingID != id else { return }
        artworkLoadingID = id
        let t0 = Date()
        Task {
            self.artworkRequests += 1
            let result = await self.loadArtwork(for: s)
            if self.artworkLoadingID == id { self.artworkLoadingID = nil }
            guard self.status?.identity == id else { return }
            let image: NSImage?
            switch result {
            case .notYet: return
            case .none: image = nil
            case .image(let i): image = i
            }
            self.artwork = (id, image)       // også "intet cover" huskes for sangen
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
