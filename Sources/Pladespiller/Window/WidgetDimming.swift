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
/// Skrivebordsfokus: Finder aktiveret uden at musen står over et Finder-vindue (klik på skrivebordet),
/// eller Finder har ingen vinduer. Mens Finder er aktiv, lytter en global musemonitor efter klik
/// (kræver ikke tilgængeligheds-tilladelse for museklik) og afgør ud fra CGWindowList om klikket
/// ramte et Finder-vindue eller skrivebordet. Monitoren findes kun mens Finder er forrest.
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

    private func applicationActivated(bundleID: String?) {
        let finder = bundleID == Self.finderBundleID
        if finder {
            desktopFocused = !Self.finderWindow(at: NSEvent.mouseLocation) || !Self.finderHasWindows()
            installClickMonitor()
        } else {
            desktopFocused = false
            removeClickMonitor()
        }
        update()
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Lad Finder/WindowServer nå at ordne vinduerne efter klikket.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID
                    else { return }
                    self.desktopFocused = !Self.finderWindow(at: NSEvent.mouseLocation)
                    self.update()
                }
            }
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
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

    /// Står punktet (AppKit-koordinater) over et almindeligt Finder-vindue?
    private static func finderWindow(at point: CGPoint) -> Bool {
        finderWindowFrames().contains { $0.contains(point) }
    }
}
