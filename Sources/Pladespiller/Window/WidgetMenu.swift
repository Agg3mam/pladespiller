import AppKit
import ServiceManagement

/// Højrekliksmenuen (som Apples widgetmenu). Bygges frisk ved hvert højreklik, så flueben altid
/// er aktuelle. Al tekst på dansk.
final class WidgetMenu {
    private let settings: Settings
    /// Menupunkternes `target` er svage referencer – handlingerne holdes her under visningen.
    private var actions: [MenuAction] = []

    init(settings: Settings) {
        self.settings = settings
    }

    /// Viser menuen ved musen. `popUp(positioning:at:in:)` kører synkront (egen sporingsløkke)
    /// og aktiverer ikke appen, så programmet brugeren arbejder i beholder fokus.
    func popUp(for event: NSEvent, in view: NSView) {
        let menu = build()
        let p = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: p, in: view)
        actions.removeAll()
    }

    func build() -> NSMenu {
        actions.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false

        for size in WidgetSize.allCases {
            menu.addItem(item(size.title, checked: settings.size == size) { [settings] in settings.size = size })
        }
        menu.addItem(.separator())

        let theme = NSMenu()
        for t in TurntableTheme.allCases {
            theme.addItem(item(t.title, checked: settings.theme == t) { [settings] in settings.theme = t })
        }
        menu.addItem(submenu("Tema", theme))

        let colors = NSMenu()
        for c in ColorMode.allCases {
            colors.addItem(item(c.title, checked: settings.colorMode == c) { [settings] in settings.colorMode = c })
        }
        menu.addItem(submenu("Farver", colors))
        menu.addItem(.separator())

        menu.addItem(item("Lås placering", checked: settings.positionLocked) { [settings] in
            settings.positionLocked.toggle()
        })
        let login = item("Åbn ved login", checked: LoginItem.isEnabled) { LoginItem.toggle() }
        if LoginItem.needsApproval { login.state = .mixed }   // afventer godkendelse i Systemindstillinger
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item("Fjern widget", checked: false) {
            // Efter menuens sporingsløkke, ikke inde i den.
            DispatchQueue.main.async { MainActor.assumeIsolated { RemoveWidget.confirmAndRemove() } }
        })
        return menu
    }

    private func item(_ title: String, checked: Bool, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let a = MenuAction(action)
        actions.append(a)
        let i = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
        i.target = a
        i.state = checked ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = sub
        return i
    }
}

private final class MenuAction: NSObject {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @objc(fire:) func fire(_ sender: Any?) { run() }
}

/// "Åbn ved login" via `SMAppService.mainApp`. Sandheden er `status`, ikke en gemt indstilling.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Afregistrér, hvis registreret (også når den afventer godkendelse).
    static func disable() {
        let service = SMAppService.mainApp
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        do { try service.unregister() } catch {
            NSLog("Pladespiller: kunne ikke fjerne fra login: \(error.localizedDescription)")
        }
    }

    static func toggle() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            // Registreret, men ikke godkendt: vis brugeren hvor det godkendes.
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Pladespiller: Åbn ved login fejlede: \(error.localizedDescription)")
        }
        // Brugeren skal godkende i Systemindstillinger ▸ Generelt ▸ Login-emner.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

/// "Fjern widget" som hos Apple: væk for altid, dvs. også fra login (QA N4).
enum RemoveWidget {
    static func confirmAndRemove() {
        // En accessory-app skal aktiveres, for at dialogen kan få fokus. Vi husker hvem der havde
        // fokus og giver det tilbage, hvis brugeren fortryder.
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Fjern Pladespiller fra skrivebordet?"
        alert.informativeText = "Den åbner ikke længere ved login."
        alert.addButton(withTitle: "Fjern")
        alert.addButton(withTitle: "Annuller").keyEquivalent = "\u{1b}"
        alert.window.level = .modalPanel
        guard alert.runModal() == .alertFirstButtonReturn else {
            if let previous, previous != NSRunningApplication.current { previous.activate() }
            return
        }
        LoginItem.disable()
        NSApp.terminate(nil)
    }
}
