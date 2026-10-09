import AppKit
import ApplicationServices

/// Flytter NYE vinduer, der åbner på fuld skærm-skærmen, over på en anden skærm (brugerens valg:
/// vinduer man selv trækker derover må blive – vi lytter kun på "window created", aldrig "moved").
///
/// Kræver Tilgængelighed. Der spørges kun, når brugeren slår funktionen til, eller fuld skærm
/// åbnes med funktionen slået til – aldrig ved opstart. Ingen polling: AXObserver pr. app (kun
/// mens fuld skærm vises), app-start/-aktivering via NSWorkspace, og adgangsændringer via den
/// distribuerede notifikation "com.apple.accessibility.api".
final class NewWindowMover {
    /// Lokal nøgle (Window-ejet). Standard: til.
    static let enabledKey = "pladespiller.fullscreen.moveNewWindows"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Skærmen fuld skærm står på (AppKit-koordinater); nil = vises ikke.
    var fullscreenScreen: () -> NSScreen? = { nil }

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var accessObserver: DistributedObserver?
    private var isRunning = false
    private var didExplainThisSession = false

    // MARK: Start/stop

    /// Kaldes når fuld skærm åbnes, eller funktionen slås til mens den vises.
    /// `askIfNeeded`: vis forklaring + åbn Systemindstillinger, hvis adgang mangler.
    func start(askIfNeeded: Bool) {
        guard Self.isEnabled else { return }
        listenForAccessChanges()
        guard AXIsProcessTrusted() else {
            if askIfNeeded { explainAccess() }
            return
        }
        guard !isRunning else { return }
        isRunning = true
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { self?.observe(app) } }
            })
        }
        workspaceObservers.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                 object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.unobserve(pid) } }
        })
        NSWorkspace.shared.runningApplications.forEach(observe)
    }

    /// Kaldes når fuld skærm lukkes, eller funktionen slås fra. Fjerner alle observere.
    func stop() {
        isRunning = false
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(ws.removeObserver)
        workspaceObservers.removeAll()
        for pid in Array(observers.keys) { unobserve(pid) }
        accessObserver = nil
    }

    var observedAppCount: Int { observers.count }

    // MARK: Adgang

    private func listenForAccessChanges() {
        guard accessObserver == nil else { return }
        accessObserver = DistributedObserver(names: ["com.apple.accessibility.api"]) { [weak self] in
            // Tilstanden opdateres lidt efter notifikationen: ét engangstjek, ingen polling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    guard let self, self.fullscreenScreen() != nil else { return }
                    self.start(askIfNeeded: false)
                }
            }
        }
    }

    private func explainAccess() {
        guard !didExplainThisSession else { return }
        didExplainThisSession = true
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Pladespiller skal have adgang til Tilgængelighed"
        alert.informativeText = """
            For at flytte nye vinduer væk fra fuld skærm-skærmen skal Pladespiller have lov til at \
            flytte vinduer. Slå Pladespiller til under Anonymitet og sikkerhed ▸ Tilgængelighed. \
            Fuld skærm virker også uden.
            """
        alert.addButton(withTitle: "Åbn Systemindstillinger")
        alert.addButton(withTitle: "Ikke nu")
        if alert.runModal() == .alertFirstButtonReturn {
            // Sørger for, at Pladespiller står på listen (uden systemets egen dialog oveni).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if let previous, previous != NSRunningApplication.current {
            previous.activate()
        }
    }

    // MARK: AXObserver pr. app

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isRunning, app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, newWindowCallback, &obs) == .success, let obs else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, refcon) == .success
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func unobserve(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(obs, AXUIElementCreateApplication(pid), kAXWindowCreatedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    // MARK: Flyt

    fileprivate func windowCreated(_ window: AXUIElement) {
        // Vent kort, så vinduet har fået sin endelige position.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated { self?.moveIfNeeded(window, attempt: 0) }
        }
    }

    private func moveIfNeeded(_ window: AXUIElement, attempt: Int) {
        guard isRunning, let fsScreen = fullscreenScreen(),
              Self.string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              Self.bool(window, "AXFullScreen") != true,
              let frameCG = Self.frame(of: window) else { return }
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let toCG = { (r: CGRect) in GridSnapper.appKitRect(fromCG: r, primaryScreenHeight: primaryHeight) }  // samme omregning begge veje
        let fsCG = toCG(fsScreen.frame)
        guard Self.fractionOnScreen(frameCG, screen: fsCG) > 0.5,
              let target = Self.destinationScreen(screens: screens, excluding: fsScreen) else { return }
        let newFrame = Self.destinationFrame(window: frameCG, from: toCG(fsScreen.visibleFrame),
                                             to: toCG(target.visibleFrame))
        Self.setFrame(window, newFrame)
        // Flytter appen det selv tilbage, prøver vi én gang til.
        guard attempt == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated { self?.moveIfNeeded(window, attempt: 1) }
        }
    }

    /// Hvor brugeren arbejder: hovedskærmen (menulinjen), medmindre det er fuld skærm-skærmen.
    static func destinationScreen(screens: [NSScreen], excluding fs: NSScreen) -> NSScreen? {
        screens.first { $0 != fs }
    }

    // MARK: Rene funktioner (CG-koordinater, origin øverst til venstre – det AX bruger)

    /// Andelen af vinduets areal, der ligger på skærmen (0…1).
    nonisolated static func fractionOnScreen(_ window: CGRect, screen: CGRect) -> CGFloat {
        let area = window.width * window.height
        guard area > 0 else { return 0 }
        let x = window.intersection(screen)
        return x.isNull ? 0 : (x.width * x.height) / area
    }

    /// Ny ramme på målskærmen: samme relative placering (midtpunktet som brøkdel af det synlige
    /// område), samme størrelse – krympet hvis større end målets synlige område – og helt indenfor.
    nonisolated static func destinationFrame(window: CGRect, from src: CGRect, to dst: CGRect) -> CGRect {
        let w = min(window.width, dst.width), h = min(window.height, dst.height)
        let fx = src.width > 0 ? (window.midX - src.minX) / src.width : 0.5
        let fy = src.height > 0 ? (window.midY - src.minY) / src.height : 0.5
        var r = CGRect(x: dst.minX + fx * dst.width - w / 2, y: dst.minY + fy * dst.height - h / 2, width: w, height: h)
        r.origin.x = min(max(r.minX, dst.minX), dst.maxX - w)
        r.origin.y = min(max(r.minY, dst.minY), dst.maxY - h)
        return r
    }

    // MARK: AX-hjælpere

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func bool(_ e: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return (v as? NSNumber)?.boolValue
    }

    private static func frame(of e: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func setFrame(_ e: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        if let size = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size) }
        if let pos = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, pos) }
        // Nogle apps begrænser størrelsen ud fra den gamle skærm: sæt størrelsen igen efter flytningen.
        if let size = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size) }
    }
}

/// AXObserver-callback (C). Kører på hovedtrådens runloop, hvor observeren er tilføjet.
nonisolated private func newWindowCallback(_ observer: AXObserver, _ element: AXUIElement,
                               _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let mover = Unmanaged<NewWindowMover>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let window = element   // callback'en kører på hovedtråden
    MainActor.assumeIsolated { mover.windowCreated(window) }
}
