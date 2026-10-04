import AppKit
import Observation

/// Hvordan det falmede look ser ud. Grafik-agenten bør matche disse værdier for pladespilleren
/// ved `dimAmount = 1` (lineær interpolation imellem). Foreslået flyttet til `WidgetMetrics`.
enum WidgetDimLook {
    /// Indholdets farvemætning når helt dæmpet (0 = gråtoner, dvs. 100 % afmætning).
    static let contentSaturation: Double = 0
    /// Indholdets opacitet når helt dæmpet.
    static let contentOpacity: Double = 0.6
    /// Skallens uigennemsigtige flade når helt dæmpet (resten er sløret skrivebord bag vinduet).
    static let backgroundOpacity: Double = 0.2
}

/// Bestemmer `presentation.dimAmount` (0 = fuld farve, 1 = dæmpet). Kun hændelser, ingen polling.
///
/// - "Altid fuld farve" / "Altid dæmpet": fast.
/// - "Automatisk": som Apples egne widgets. Systemets Widgetstil (`com.apple.widgets widgetAppearance`)
///   afgør: Fuld farve (= 1, målt hos brugeren: Apples widgets forbliver i fuld farve, også når et
///   andet program er aktivt) → aldrig dæmpet. Ellers: fuld farve når Finder er aktiv og skrivebordet
///   har fokus, dæmpet i alle andre tilfælde.
///
/// Skrivebordsfokus: Finder blev aktiveret af et klik (< 0,75 s før) der ikke ramte noget almindeligt
/// vindue, eller Finder har ingen vinduer. Cmd+Tab/Dock til Finder med vinduer = Finder-vindue i fokus
/// (QA N5). En global musemonitor (kræver ikke tilgængeligheds-tilladelse for museklik) gemmer blot
/// tid og sted for hvert klik; mens Finder er forrest, afgør den også om et klik ramte skrivebordet.
final class WidgetDimming {
    /// Systemets widgetstil, så vidt den kendes.
    nonisolated enum SystemPolicy: Equatable { case automatic, fullColor }

    nonisolated static func systemPolicy(widgetAppearance: Int?) -> SystemPolicy {
        // 1 = Fuld farve (udledt: brugeren har 1, og Apples widgets dæmpes ikke når andre apps er aktive).
        // Andre værdier er ikke bekræftet → behandles som Automatisk.
        widgetAppearance == 1 ? .fullColor : .automatic
    }

    /// Ren funktion for målværdien.
    nonisolated static func target(mode: ColorMode, policy: SystemPolicy, desktopFocused: Bool) -> Double {
        switch mode {
        case .alwaysFull: 0
        case .alwaysDimmed: 1
        case .automatic: (policy == .fullColor || desktopFocused) ? 0 : 1
        }
    }

    private let settings: Settings
    private let style: WidgetStyle
    private let presentation: WidgetPresentation
    private var desktopFocused = false
    private var activationObserver: NSObjectProtocol?
    private var clickMonitor: Any?

    static let finderBundleID = "com.apple.finder"

    init(settings: Settings, style: WidgetStyle, presentation: WidgetPresentation) {
        self.settings = settings
        self.style = style
        self.presentation = presentation
    }

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.applicationActivated(bundleID: bundleID) }
        }
        installClickMonitor()
        applicationActivated(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        observeInputs()
    }

    private func observeInputs() {
        withObservationTracking {
            _ = settings.colorMode
            _ = style.widgetAppearance
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observeInputs()
            }
        }
    }

    /// Seneste globale klik (tid + sted). Bruges til at skelne "Finder aktiveret ved klik på
    /// skrivebordet" fra Cmd+Tab/Dock (QA N5). Monitoren gemmer kun to værdier pr. klik.
    private var lastClick: (time: TimeInterval, location: CGPoint)?

    private func applicationActivated(bundleID: String?) {
        guard bundleID == Self.finderBundleID else {
            desktopFocused = false
            update()
            return
        }
        // Klikket der aktiverede Finder kan nå monitoren lidt efter aktiveringen: vent ét øjeblik
        // (engangsforsinkelse, ingen polling), så vi ikke blinker dæmpet → fuld farve.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let recent = self.lastClick.flatMap { now - $0.time < 0.75 ? $0.location : nil }
                self.desktopFocused = Self.desktopFocusOnFinderActivation(
                    clickedDesktop: recent.map { !Self.normalWindowExists(at: $0) },
                    finderHasWindows: Self.finderHasWindows())
                self.update()
            }
        }
    }

    /// Ren funktion. `clickedDesktop`: nil = ingen frisk klik (Cmd+Tab, tastatur), true = klik ramte
    /// intet almindeligt vindue (skrivebordet), false = klik på et vindue/Dock.
    nonisolated static func desktopFocusOnFinderActivation(clickedDesktop: Bool?, finderHasWindows: Bool) -> Bool {
        if clickedDesktop == true { return true }
        // Cmd+Tab, Dock eller klik i et Finder-vindue: et Finder-vindue får fokus, hvis der er et.
        return !finderHasWindows
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            let time = ProcessInfo.processInfo.systemUptime
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastClick = (time, location)
                // Klik mens Finder allerede er forrest: skrivebord eller Finder-vindue?
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID else { return }
                // Lad WindowServer nå at ordne vinduerne efter klikket.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID
                        else { return }
                        self.desktopFocused = !Self.normalWindowExists(at: location)
                        self.update()
                    }
                }
            }
        }
    }

    private func update() {
        let t = Self.target(mode: settings.colorMode,
                            policy: Self.systemPolicy(widgetAppearance: style.widgetAppearance),
                            desktopFocused: desktopFocused)
        if presentation.dimAmount != t { presentation.dimAmount = t }
    }

    // MARK: CGWindowList (kun lag, ejer og rammer – ingen skærmoptagelses-tilladelse)

    private static func finderWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let finderPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID)
            .map(\.processIdentifier))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, finderPIDs.contains(pid),
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict), r.width > 40, r.height > 40 else { return nil }
            return GridSnapper.appKitRect(fromCG: r, primaryScreenHeight: primaryHeight)
        }
    }

    private static func finderHasWindows() -> Bool { !finderWindowFrames().isEmpty }

    /// Står punktet (AppKit-koordinater) over et almindeligt vindue, Dock eller lignende (lag 0…20)?
    /// Ellers er det skrivebordet. Notifikationscentrets gennemsigtige fuldskærmsvindue og vores
    /// egne vinduer tæller ikke.
    private static func normalWindowExists(at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ncPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: AppleWidgetWindows.ownerBundleID)
            .map(\.processIdentifier))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.contains { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, (0...20).contains(layer),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID, !ncPIDs.contains(pid),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { return false }
            return GridSnapper.appKitRect(fromCG: r, primaryScreenHeight: primaryHeight).contains(point)
        }
    }
}
