import AppKit
import Observation
import SwiftUI

/// Det kantløse vindue nede på skrivebordet. Ejes af Vindue-agenten.
///
/// Træk: `sendEvent(_:)` sender mouseDown og små bevægelser videre til SwiftUI. Først når musen
/// har flyttet sig mere end `WidgetMetrics.dragThreshold` (og indholdet ikke har gjort krav på
/// trækket, og placeringen ikke er låst), overtager vinduet: SwiftUI får et "mouseUp langt væk"
/// (så knapper/tap annulleres), og vinduet flyttes selv. Ingen `isMovableByWindowBackground`.
final class WidgetPanel: NSPanel {
    let dragClaim = WidgetDragClaim()
    var isPositionLocked: () -> Bool = { false }
    var onDragBegan: () -> Void = {}
    var onDragMoved: (CGPoint) -> Void = { _ in }   // ny origin (AppKit)
    var onDragEnded: () -> Void = {}
    var onContextMenu: (NSEvent) -> Void = { _ in }
    /// Ctrl-klik åbnede menuen: slug resten af venstreklikket.
    private var swallowLeftMouse = false

    private var mouseDownLocation: CGPoint?
    private var originAtMouseDown: CGPoint = .zero
    private(set) var isDragging = false

    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = WidgetMetrics.windowLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false               // vi flytter selv
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if swallowLeftMouse, event.type == .leftMouseDragged || event.type == .leftMouseUp {
            if event.type == .leftMouseUp { swallowLeftMouse = false }
            return
        }
        switch event.type {
        case .rightMouseDown:
            onContextMenu(event)

        case .leftMouseDown where event.modifierFlags.contains(.control):
            swallowLeftMouse = true
            mouseDownLocation = nil
            onContextMenu(event)

        case .leftMouseDown:
            swallowLeftMouse = false
            isDragging = false
            dragClaim.isClaimed = false
            mouseDownLocation = NSEvent.mouseLocation
            originAtMouseDown = frame.origin
            super.sendEvent(event)

        case .leftMouseDragged:
            let p = NSEvent.mouseLocation
            if isDragging {
                moveWithMouse(p)
                return
            }
            if let start = mouseDownLocation,
               !dragClaim.isClaimed, !isPositionLocked(),
               hypot(p.x - start.x, p.y - start.y) > WidgetMetrics.dragThreshold {
                isDragging = true
                cancelContentTracking(like: event)
                onDragBegan()
                moveWithMouse(p)
                return
            }
            super.sendEvent(event)

        case .leftMouseUp:
            mouseDownLocation = nil
            if isDragging {
                isDragging = false
                onDragEnded()
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func moveWithMouse(_ p: CGPoint) {
        guard let start = mouseDownLocation else { return }
        onDragMoved(CGPoint(x: originAtMouseDown.x + p.x - start.x,
                            y: originAtMouseDown.y + p.y - start.y))
    }

    /// Afslut SwiftUI's igangværende museforløb med et mouseUp langt uden for vinduet,
    /// så en knap ikke udløses og en tap-gesture fejler.
    private func cancelContentTracking(like event: NSEvent) {
        guard let up = NSEvent.mouseEvent(with: .leftMouseUp,
                                          location: NSPoint(x: -100_000, y: -100_000),
                                          modifierFlags: event.modifierFlags,
                                          timestamp: event.timestamp,
                                          windowNumber: windowNumber,
                                          context: nil,
                                          eventNumber: event.eventNumber,
                                          clickCount: 1,
                                          pressure: 0) else { return }
        super.sendEvent(up)
    }
}

/// NSHostingView der tager imod første klik, selvom vinduet aldrig bliver key.
/// Sporer også hover over den synlige flade (`.activeAlways`, fordi panelet aldrig er key).
final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: (Bool) -> Void = { _ in }
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let rect = bounds.insetBy(dx: WidgetMetrics.windowInset, dy: WidgetMetrics.windowInset)
        let a = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        hoverArea = a
        // Står musen allerede over fladen (fx efter størrelsesskift)?
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            onHoverChanged(rect.contains(p))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHoverChanged(true) } else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHoverChanged(false) } else { super.mouseExited(with: event) }
    }
}

/// Opretter panelet og holder SwiftUI-indholdet. Står for placering, træk, gitter,
/// skærmskift og størrelsesskift. Ingen timere: alt sker på hændelser.
final class WidgetPanelController {
    /// Sættes af App.swift; menuen ▸ "Fuld skærm" bruger den.
    var fullscreen: FullscreenController? { didSet { menu.fullscreen = fullscreen } }
    private let settings: Settings
    private let style = WidgetStyle()
    private let panel: WidgetPanel
    private let landing = LandingShadow()
    private var dragAnchors: [CGRect] = []
    private var screenObserver: NSObjectProtocol?

    /// Skærmen widgetten sidst blev placeret på af brugeren. Gemmes her (Window-ejet nøgle),
    /// så gendannelse vælger rigtig skærm, når flere har en gemt placering.
    private let presentation = WidgetPresentation()
    private lazy var dimming = WidgetDimming(settings: settings, style: style, presentation: presentation)
    private lazy var menu = WidgetMenu(settings: settings)
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Gammel Window-ejet nøgle fra bølge 1; flyttes én gang til `settings.lastScreenID` (QA K3).
    private static let legacyLastScreenKey = "pladespiller.window.lastScreen"
    private var lastScreenID: String? {
        get { settings.lastScreenID }
        set { settings.lastScreenID = newValue }
    }

    private func migrateLegacyLastScreen() {
        let d = UserDefaults.standard
        guard let old = d.string(forKey: Self.legacyLastScreenKey) else { return }
        if settings.lastScreenID == nil { settings.lastScreenID = old }
        d.removeObject(forKey: Self.legacyLastScreenKey)
    }

    init<Content: View>(settings: Settings, @ViewBuilder content: () -> Content) {
        self.settings = settings
        let size = WidgetMetrics.windowSize(for: settings.size)
        panel = WidgetPanel(size: size)
        let root = WidgetChrome(content: content())
            .environment(settings)
            .environment(style)
            .environment(\.widgetDragClaim, panel.dragClaim)
            .environment(\.widgetPresentation, presentation)
        let host = WidgetHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.isPositionLocked = { [weak settings] in settings?.positionLocked ?? false }
        panel.onDragBegan = { [weak self] in self?.dragBegan() }
        panel.onDragMoved = { [weak self] in self?.dragMoved(to: $0) }
        panel.onDragEnded = { [weak self] in self?.dragEnded() }
        panel.onContextMenu = { [weak self, weak host] event in
            guard let self, let host else { return }
            self.menu.popUp(for: event, in: host)
        }
        host.onHoverChanged = { [weak self] hovering in
            guard let self, self.presentation.isHovering != hovering else { return }
            self.presentation.isHovering = hovering
        }

        migrateLegacyLastScreen()
        migratePlacementToTopLeft()
        applyAppearance()
        observeStyle()
        observeSize()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.placeAfterScreenChange()
                // Apple lægger sine widgets om efter et skærmskift – flugt igen bagefter.
                self?.scheduleRealign(after: 2)
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        // Efter dvale, skærme der vågner og brugerskift tegner Apple sine widgets igen (QA N10).
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRealign(after: 1)
                    self?.scheduleRealign(after: 5)
                }
            })
        }
        workspaceObservers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.realignToAppleWidgets() }
        })
        workspaceObservers.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                 object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == AppleWidgetWindows.ownerBundleID else { return }
            MainActor.assumeIsolated { self?.scheduleRealign(after: 2) }
        })
    }

    func show() {
        panel.setFrame(desiredFrame(size: WidgetMetrics.windowSize(for: settings.size)), display: false)
        panel.orderFrontRegardless()
        dimming.start()
        // Ved login er Apples widgets måske ikke tegnet endnu (QA M7/N10): en kort, endelig række
        // engangstjek – ingen gentagen polling. Står vi allerede rigtigt, sker der intet.
        for delay in [1.5, 4, 10, 30, 60] as [TimeInterval] { scheduleRealign(after: delay) }
    }

    // MARK: Flugt med Apple-widgets der dukker op senere (QA M7)

    private func scheduleRealign(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.realignToAppleWidgets() }
        }
    }

    /// Placér igen ud fra brugerens ønskede plads og Apples widgets som de står nu.
    /// Gemmer ikke: brugerens egen placering bevares til næste gendannelse.
    private func realignToAppleWidgets() {
        guard !panel.isDragging else { return }
        let target = desiredFrame(size: panel.frame.size)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = WidgetMetrics.snapDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    // MARK: Udseende

    private func applyAppearance() {
        panel.appearance = style.nsAppearance
    }

    private func observeStyle() {
        withObservationTracking {
            _ = style.nsAppearance
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyAppearance()
                self?.observeStyle()
            }
        }
    }

    // MARK: Størrelse

    private func observeSize() {
        withObservationTracking {
            _ = settings.size
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sizeChanged()
                self?.observeSize()
            }
        }
    }

    /// Ny størrelse ud fra det samme øverste venstre hjørne (brugerens gemte plads), snap igen.
    /// Gemmer ikke: måtte widgetten vige for en Apple-widget i den store størrelse, kommer den
    /// tilbage på sin plads, når den bliver mindre igen (QA N15).
    private func sizeChanged() {
        let size = WidgetMetrics.windowSize(for: settings.size)
        guard panel.frame.size != size else { return }
        panel.setFrame(desiredFrame(size: size), display: true)
    }

    // MARK: Træk

    private func dragBegan() {
        dragAnchors = AppleWidgetWindows.frames()
        panel.orderFrontRegardless()
        landing.show(at: snapped(panel.frame, anchors: dragAnchors), below: panel)
    }

    private func dragMoved(to origin: CGPoint) {
        panel.setFrameOrigin(origin)
        landing.move(to: snapped(panel.frame, anchors: dragAnchors))
    }

    private func dragEnded() {
        let target = snapped(panel.frame, anchors: dragAnchors)
        landing.hide()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = WidgetMetrics.snapDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
        }
        save(target)
    }

    // MARK: Placering

    private func screen(for frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        return GridSnapper.bestScreenIndex(for: frame, visibleFrames: screens.map(\.visibleFrame))
            .map { screens[$0] }
    }

    private func snapped(_ frame: CGRect, anchors: [CGRect]? = nil) -> CGRect {
        guard let screen = screen(for: frame) else { return frame }
        let visible = screen.visibleFrame
        let a = anchors ?? AppleWidgetWindows.frames()
        let start = GridSnapper.clamp(frame, into: visible)
        return GridSnapper.snap(start, visibleFrame: visible, anchors: a, pitch: WidgetMetrics.gridPitch)
    }

    /// Gemmer brugerens plads som **øverste venstre hjørne** (x, maxY i AppKit-koordinater), så den
    /// gælder for alle størrelser (QA N15). Kun ved træk.
    private func save(_ frame: CGRect) {
        guard let screen = screen(for: frame) else { return }
        let id = screen.stableID
        settings.saveOrigin(CGPoint(x: frame.minX, y: frame.maxY), screenID: id)
        lastScreenID = id
    }

    /// Bølge 1/2 gemte nederste venstre hjørne. Omregn én gang til øverste venstre ud fra den
    /// størrelse der var aktiv (størrelsesskift gemte dengang ny placering, så den passer).
    private static let topLeftMarkerKey = "pladespiller.window.placementIsTopLeft"
    private func migratePlacementToTopLeft() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.topLeftMarkerKey) else { return }
        let h = WidgetMetrics.windowSize(for: settings.size).height
        let prefix = Settings.Key.placement(screenID: "")
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let id = String(key.dropFirst(prefix.count))
            if let o = settings.savedOrigin(screenID: id) {
                settings.saveOrigin(CGPoint(x: o.x, y: o.y + h), screenID: id)
            }
        }
        d.set(true, forKey: Self.topLeftMarkerKey)
    }

    /// Hvor widgetten skal stå med `size`: på den sidst brugte skærm (eller en anden med gemt plads)
    /// ud fra det gemte øverste venstre hjørne; er den sidste skærm væk, bliver den hvor den er.
    private func desiredFrame(size: CGSize) -> CGRect {
        if let last = lastScreenID, !NSScreen.screens.contains(where: { $0.stableID == last }) {
            let f = panel.frame
            return snapped(CGRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height))
        }
        return restoredFrame(size: size)
    }

    /// Gendan: sidste skærm hvis den er tilsluttet, ellers første skærm med en gemt placering,
    /// ellers øverst til venstre på hovedskærmen (som Apples første widget-gruppe).
    private func restoredFrame(size: CGSize) -> CGRect {
        let screens = NSScreen.screens
        var ordered = screens
        if let last = lastScreenID, let i = screens.firstIndex(where: { $0.stableID == last }) {
            ordered.insert(ordered.remove(at: i), at: 0)
        }
        for screen in ordered {
            if let topLeft = settings.savedOrigin(screenID: screen.stableID) {
                let saved = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
                let visible = screen.visibleFrame
                let start = GridSnapper.clamp(saved, into: visible)
                return GridSnapper.snap(start, visibleFrame: visible,
                                        anchors: AppleWidgetWindows.frames(), pitch: WidgetMetrics.gridPitch)
            }
        }
        guard let main = NSScreen.main ?? screens.first else { return CGRect(origin: .zero, size: size) }
        let v = main.visibleFrame
        return snapped(CGRect(x: v.minX, y: v.maxY - size.height, width: size.width, height: size.height))
    }

    /// Skærm til/fra, opløsning, Dock eller menulinje ændret.
    /// Kommer den sidst brugte skærm tilbage, går vi tilbage dertil; ellers bliver vi hvor vi er,
    /// hvis det stadig er synligt, og flytter ellers til nærmeste synlige sted.
    private func placeAfterScreenChange() {
        guard !panel.isDragging else { return }
        let target = desiredFrame(size: panel.frame.size)
        if target != panel.frame { panel.setFrame(target, display: true) }
    }
}
