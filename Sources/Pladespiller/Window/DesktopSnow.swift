import AppKit
import Observation

/// Sne på skrivebordet i julestemningen: ét gennemsigtigt vindue pr. skærm lige over baggrundsbilledet – under
/// skrivebordsikoner, widgets og alle vinduer – som klik går lige igennem. Sneen er den samme som i widgetten
/// (Core Animation), så appen bruger ikke CPU på det. Vises kun, når julestemningen er tændt og
/// "Sne på skrivebordet" er slået til.
final class DesktopSnowController {
    private let settings: Settings
    private var windows: [String: NSWindow] = [:]
    private var screenObserver: NSObjectProtocol?
    private var dayTimer: Timer?

    /// Lige under skrivebordsikonerne (og dermed over baggrundsbilledet).
    static var level: NSWindow.Level { NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1) }

    init(settings: Settings) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // "Automatisk i julen" skifter ved midnat: tjek én gang i timen (ingen løbende arbejde ellers).
        dayTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        observe()
        update()
    }

    private func observe() {
        withObservationTracking {
            _ = settings.christmas
            _ = settings.desktopSnow
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private var shouldShow: Bool { settings.christmas.isActive() && settings.desktopSnow }

    private func update() {
        guard shouldShow else {
            windows.values.forEach { $0.orderOut(nil); $0.close() }
            windows.removeAll()
            return
        }
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.stableID))
        for (id, w) in windows where !ids.contains(id) {
            w.orderOut(nil); w.close(); windows[id] = nil
        }
        for screen in screens {
            let w = windows[screen.stableID] ?? makeWindow()
            if w.frame != screen.frame { w.setFrame(screen.frame, display: true) }
            (w.contentView as? ChristmasNSView)?.configure(scale: 2, snow: true, lights: false, running: true)
            w.orderFrontRegardless()
            windows[screen.stableID] = w
        }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = Self.level
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.contentView = ChristmasNSView(frame: .zero)
        return w
    }
}
