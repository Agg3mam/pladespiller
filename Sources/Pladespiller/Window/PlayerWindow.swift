import AppKit
import SwiftUI

/// Pladespilleren som et almindeligt vindue (menu ▸ Åbn som vindue): kan flyttes, ændre størrelse og ligge foran
/// andre vinduer. Viser det samme som fuld skærm (pladespiller + sangtekst), tilpasset vinduets størrelse.
/// Mens vinduet er åbent, er appen en almindelig app (ikon i Dock, ⌘-Tab); når det lukkes, bliver den igen en
/// ren baggrundsapp med widgetten.
final class PlayerWindowController: NSObject, NSWindowDelegate {
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    /// Kaldes når vinduet åbner/lukker (fx så menuens flueben kan opdateres).
    var onShowingChanged: (Bool) -> Void = { _ in }

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        // Indholdet går helt op under den gennemsigtige titellinje.
        makeContent = { AnyView(content().ignoresSafeArea()) }
    }

    var isShowing: Bool { window != nil }

    func toggle() { isShowing ? close() : show() }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Pladespiller"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 480, height: 280)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: makeContent())
        if !w.setFrameUsingName("PladespillerVindue") { w.center() }
        w.setFrameAutosaveName("PladespillerVindue")
        window = w
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        onShowingChanged(true)
    }

    func close() { window?.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        // Tilbage til baggrundsapp (ingen Dock-ikon); widgetten kører videre.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                self.onShowingChanged(false)
            }
        }
    }

    /// En lille programmenu, så ⌘W, ⌘M og ⌘H virker, mens appen er en almindelig app.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Skjul Pladespiller", "Hide Pladespiller"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Afslut Pladespiller", "Quit Pladespiller"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("Vindue", "Window"))
        windowMenu.addItem(withTitle: L("Luk vindue", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L("Minimer", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}
