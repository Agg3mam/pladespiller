import AppKit
import IOKit.pwr_mgt
import Observation
import SwiftUI

/// Fuld skærm på en (helst ekstra) skærm som "nu spiller"-display. Ejes af Vindue-agenten.
///
/// **Valg: en levende baggrund på skrivebordsniveau** (`desktopIconWindow + 1` = -2147483602), der
/// dækker hele `screen.frame`, med `.canJoinAllSpaces, .stationary, .ignoresCycle`.
/// - Alle almindelige vinduer (nye og flyttede), Dock og menulinjen ligger foran (brugerens ønske:
///   "nye apps må ikke åbne bagved").
/// - Over skrivebordsikoner (-2147483603) og baggrundsbillede; under vores egen widget og Apples
///   widgets (-2147483601), så de ikke forsvinder.
/// - Står stille ved Space-skift og i Mission Control som skrivebordet (`.stationary`).
/// Ikke `toggleFullScreen` i eget Space: med "Skærme har separate Spaces" slået fra gør det alle
/// skærme sorte, Spaces kan flyttes af swipes/Mission Control, og overgangen stjæler fokus.
final class FullscreenController {
    private let settings: Settings
    private let makeContent: () -> AnyView
    private var window: FullscreenWindow?
    private var screenID: String?
    private var screenObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private let awake = DisplayAwakeAssertion()
    /// Flytter nye vinduer væk fra fuld skærm-skærmen (kun mens den vises).
    let windowMover = NewWindowMover()
    /// Programmet der havde fokus, før et klik på fuld skærm aktiverede os.
    private var previousApp: NSRunningApplication?

    /// Om der spilles lige nu. Sættes udefra (se `observePlaying`).
    var isPlaying = false { didSet { if isPlaying != oldValue { updateAssertion() } } }

    /// Kaldes når fuld skærm åbner/lukker (fx så menuens flueben kan opdateres).
    var onShowingChanged: (Bool) -> Void = { _ in }

    init<Content: View>(settings: Settings, @ViewBuilder content: @escaping () -> Content) {
        self.settings = settings
        self.makeContent = { AnyView(content()) }
        windowMover.fullscreenScreen = { [weak self] in
            guard let self, self.window != nil else { return nil }
            return NSScreen.screens.first { $0.stableID == self.screenID }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.awake.release() }
        }
        observeSettings()
    }

    /// Følg om der spilles, fx `fullscreen.observePlaying { store.current?.isPlaying ?? false }`.
    /// Læser closure'n observerbare egenskaber, opdateres `isPlaying` uden polling.
    func observePlaying(_ read: @escaping @MainActor () -> Bool) {
        let value = withObservationTracking { read() } onChange: { [weak self] in
            Task { @MainActor in self?.observePlaying(read) }
        }
        isPlaying = value
    }

    var isShowing: Bool { window != nil }

    /// Menuen ▸ "Flyt nye vinduer væk".
    var movesNewWindows: Bool {
        get { NewWindowMover.isEnabled }
        set {
            NewWindowMover.isEnabled = newValue
            if !newValue { windowMover.stop() } else if isShowing { windowMover.start(askIfNeeded: true) }
        }
    }
    var holdsDisplayAwake: Bool { awake.isHeld }

    func toggle() { isShowing ? hide() : show() }

    func show() {
        guard window == nil, let screen = targetScreen() else { return }
        let w = FullscreenWindow(screen: screen)
        w.contentView = FullscreenHostingView(rootView: makeContent())
        w.onEscape = { [weak self] in self?.hide() }
        w.onClick = { [weak self] in self?.clicked() }
        window = w
        screenID = screen.stableID
        // Åbn uden at aktivere: fokus bliver hos det brugeren arbejder i på hovedskærmen.
        w.orderFrontRegardless()
        updateAssertion()
        windowMover.start(askIfNeeded: true)
        onShowingChanged(true)
    }

    func hide() {
        guard let w = window else { return }
        window = nil
        screenID = nil
        windowMover.stop()
        w.cancelCursorHiding()
        NSCursor.setHiddenUntilMouseMoves(false)
        w.orderOut(nil)
        w.close()
        updateAssertion()
        if NSApp.isActive, let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
        onShowingChanged(false)
    }

    // MARK: Skærm

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let ids = screens.map(\.stableID)
        let widgetScreen = settings.lastScreenID
        guard let id = Self.chooseScreen(screenIDs: ids, preferredID: settings.fullscreenScreenID,
                                         widgetScreenID: widgetScreen) else { return nil }
        return screens.first { $0.stableID == id }
    }

    /// Ren funktion. `screenIDs[0]` er hovedskærmen (menulinjen). Valgt skærm hvis tilsluttet;
    /// ellers en ekstra skærm, helst ikke den widgetten står på; ellers hovedskærmen.
    nonisolated static func chooseScreen(screenIDs: [String], preferredID: String?, widgetScreenID: String?) -> String? {
        if let p = preferredID, screenIDs.contains(p) { return p }
        let extra = Array(screenIDs.dropFirst())
        if let free = extra.first(where: { $0 != widgetScreenID }) { return free }
        return extra.first ?? screenIDs.first
    }

    private func screensChanged() {
        guard let w = window else { return }
        guard let screen = NSScreen.screens.first(where: { $0.stableID == screenID }) else {
            hide()      // skærmen er taget ud: luk pænt; åbn ikke af sig selv igen
            return
        }
        if w.frame != screen.frame { w.setFrame(screen.frame, display: true) }   // ny opløsning
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.fullscreenScreenID
            _ = settings.keepDisplayAwake
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.settingsChanged()
                self?.observeSettings()
            }
        }
    }

    private func settingsChanged() {
        updateAssertion()
        // Ny skærm valgt mens fuld skærm vises: flyt derhen.
        if let w = window, let screen = targetScreen(), screen.stableID != screenID {
            screenID = screen.stableID
            w.setFrame(screen.frame, display: true)
        }
    }

    // MARK: Klik, fokus, cursor

    private func clicked() {
        // Klik på fuld skærm: brugeren vil hertil. Aktivér, så Esc og skjult cursor virker.
        if !NSApp.isActive {
            let front = NSWorkspace.shared.frontmostApplication
            if front != NSRunningApplication.current { previousApp = front }
            NSApp.activate()
        }
        // Kun key – ikke orderFront: vinduet må ikke komme foran brugerens vinduer. (På skrivebords-
        // niveau kan det heller ikke, men vi rører ikke rækkefølgen.)
        window?.makeKey()
    }

    // MARK: Hold skærmen tændt

    nonisolated static func shouldHoldDisplayAwake(keepAwake: Bool, showing: Bool, playing: Bool) -> Bool {
        keepAwake && showing && playing
    }

    private func updateAssertion() {
        if Self.shouldHoldDisplayAwake(keepAwake: settings.keepDisplayAwake, showing: isShowing, playing: isPlaying) {
            awake.take()
        } else {
            awake.release()
        }
    }
}

/// IOKit-assertion der forhindrer skærmen i at gå i dvale, mens fuld skærm viser noget der spiller.
final class DisplayAwakeAssertion {
    private var id: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    var isHeld: Bool { id != IOPMAssertionID(kIOPMNullAssertionID) }

    func take() {
        guard !isHeld else { return }
        var newID = IOPMAssertionID(kIOPMNullAssertionID)
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Pladespiller viser fuld skærm" as CFString, &newID)
        if r == kIOReturnSuccess { id = newID }
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        id = IOPMAssertionID(kIOPMNullAssertionID)
    }

    isolated deinit { release() }
}

/// Kantløst vindue over hele skærmen. Kan blive key (Esc), uden at aktivere appen ved visning.
final class FullscreenWindow: NSPanel {
    var onEscape: () -> Void = {}
    var onClick: () -> Void = {}
    private var hideCursorWork: DispatchWorkItem?
    static let cursorIdle: TimeInterval = 3
    /// Lige under widgetniveauet (Apples og vores widgets: desktopIconWindow + 2).
    static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    static let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = Self.windowLevel
        collectionBehavior = Self.behavior
        isOpaque = true
        backgroundColor = .black            // indtil indholdet tegner
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            NSCursor.setHiddenUntilMouseMoves(false)
            onClick()
            scheduleCursorHiding()
        case .mouseMoved, .leftMouseDragged:
            scheduleCursorHiding()
        case .keyDown where event.keyCode == 53:   // Esc
            onEscape()
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { onEscape() }

    /// Er det øverste vindue under musen vores (ikke et vindue, Dock eller widget foran)?
    var isTopmostUnderMouse: Bool {
        let p = NSEvent.mouseLocation
        return frame.contains(p) && NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0) == windowNumber
    }

    /// Skjul cursoren efter 3 s uden bevægelse – kun hvis den står direkte over dette vindue.
    /// Engangsforsinkelse der kun startes af musebevægelse (ingen løbende timer).
    func scheduleCursorHiding() {
        hideCursorWork?.cancel()
        guard isTopmostUnderMouse else { hideCursorWork = nil; return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, self.isTopmostUnderMouse else { return }
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        hideCursorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorIdle, execute: work)
    }

    func cancelCursorHiding() {
        hideCursorWork?.cancel()
        hideCursorWork = nil
    }
}

/// Hosting-view med musebevægelser (`.activeAlways`, vinduet er sjældent key) og første klik.
final class FullscreenHostingView: NSHostingView<AnyView> {
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseMoved(with event: NSEvent) {
        (window as? FullscreenWindow)?.scheduleCursorHiding()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        (window as? FullscreenWindow)?.scheduleCursorHiding()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        (window as? FullscreenWindow)?.cancelCursorHiding()
        super.mouseExited(with: event)
    }
}
