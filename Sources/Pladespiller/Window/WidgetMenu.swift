import AppKit
import ServiceManagement

/// Højrekliksmenuen (som Apples widgetmenu). Bygges frisk ved hvert højreklik, så flueben altid
/// er aktuelle. Al tekst på dansk.
final class WidgetMenu {
    private let settings: Settings
    /// Fuld skærm (sættes af `WidgetPanelController`). Nil → punkterne vises ikke.
    var fullscreen: FullscreenController?
    /// Tilsluttede skærme (id, navn); kan erstattes i selvtesten.
    var screens: () -> [(id: String, name: String)] = {
        NSScreen.screens.map { ($0.stableID, $0.localizedName) }
    }
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
        menu.addItem(submenu(L("Tema", "Theme"), theme))
        menu.addItem(submenu(L("Farve", "Color"), flatColorMenu()))

        let speed = NSMenu()
        for v in SpinSpeed.allCases {
            speed.addItem(item(v.title, checked: settings.spinSpeed == v) { [settings] in settings.spinSpeed = v })
        }
        menu.addItem(submenu(L("Hastighed", "Speed"), speed))

        let colors = NSMenu()
        for c in ColorMode.allCases {
            colors.addItem(item(c.title, checked: settings.colorMode == c) { [settings] in settings.colorMode = c })
        }
        menu.addItem(submenu(L("Dæmpning", "Dimming"), colors))

        let christmas = NSMenu()
        for c in ChristmasMode.allCases {
            christmas.addItem(item(c.title, checked: settings.christmas == c) { [settings] in settings.christmas = c })
        }
        christmas.addItem(.separator())
        christmas.addItem(item(L("Sne på skrivebordet", "Snow on the desktop"), checked: settings.desktopSnow) { [settings] in
            settings.desktopSnow.toggle()
        })
        menu.addItem(submenu(L("Julestemning", "Christmas mood"), christmas))
        menu.addItem(.separator())

        menu.addItem(item(L("Vis knapper og tekst", "Show controls and text"), checked: settings.showControls) { [settings] in
            settings.showControls.toggle()
        })
        let lyrics = item(L("Vis sangtekst", "Show lyrics"), checked: settings.showLyrics) { [settings] in
            settings.showLyrics.toggle()
        }
        lyrics.toolTip = L("Henter fra LRCLIB på nettet", "Fetched from LRCLIB online")
        menu.addItem(lyrics)
        menu.addItem(note(L("Henter fra LRCLIB på nettet", "Fetched from LRCLIB online")))
        menu.addItem(.separator())

        if let fullscreen {
            addFullscreenItems(to: menu, fullscreen)
            menu.addItem(.separator())
        }

        let language = NSMenu()
        for c in LanguageChoice.allCases {
            language.addItem(item(c.title, checked: AppLanguage.shared.choice == c) { AppLanguage.shared.choice = c })
        }
        menu.addItem(submenu(L("Sprog", "Language"), language))
        menu.addItem(item(L("Lås placering", "Lock position"), checked: settings.positionLocked) { [settings] in
            settings.positionLocked.toggle()
        })
        let login = item(L("Åbn ved login", "Open at login"), checked: LoginItem.isEnabled) { LoginItem.toggle() }
        if LoginItem.needsApproval { login.state = .mixed }   // afventer godkendelse i Systemindstillinger
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item(L("Fjern widget", "Remove widget"), checked: false) {
            // Efter menuens sporingsløkke, ikke inde i den.
            DispatchQueue.main.async { MainActor.assumeIsolated { RemoveWidget.confirmAndRemove() } }
        })
        return menu
    }

    /// Fuld skærm, Fuld skærm-visning ▸, Fuld skærm-skærm ▸ (kun ved flere skærme), Hold skærmen tændt.
    private func addFullscreenItems(to menu: NSMenu, _ fullscreen: FullscreenController) {
        let toggle = item(L("Fuld skærm", "Full screen"), checked: fullscreen.isShowing) { [weak fullscreen] in
            // Efter menuens sporingsløkke.
            DispatchQueue.main.async { MainActor.assumeIsolated { fullscreen?.toggle() } }
        }
        toggle.toolTip = L("Esc lukker", "Esc closes")
        menu.addItem(toggle)

        let layout = NSMenu()
        for l in FullscreenLayout.allCases {
            layout.addItem(item(l.title, checked: settings.fullscreenLayout == l) { [settings] in
                settings.fullscreenLayout = l
            })
        }
        menu.addItem(submenu(L("Fuld skærm-visning", "Full screen view"), layout))

        let list = screens()
        if list.count > 1 {
            let sm = NSMenu()
            sm.addItem(item(L("Automatisk", "Automatic"), checked: settings.fullscreenScreenID == nil) { [settings] in
                settings.fullscreenScreenID = nil
            })
            sm.addItem(.separator())
            for s in list {
                sm.addItem(item(s.name, checked: settings.fullscreenScreenID == s.id) { [settings] in
                    settings.fullscreenScreenID = s.id
                })
            }
            menu.addItem(submenu(L("Fuld skærm-skærm", "Full screen display"), sm))
        }

        menu.addItem(item(L("Hold skærmen tændt", "Keep display awake"), checked: settings.keepDisplayAwake) { [settings] in
            settings.keepDisplayAwake.toggle()
        })
        let move = item(L("Flyt nye vinduer væk", "Move new windows away"), checked: fullscreen.movesNewWindows) { [weak fullscreen] in
            // Efter menuens sporingsløkke (kan vise en forklaring om Tilgængelighed).
            DispatchQueue.main.async {
                MainActor.assumeIsolated { fullscreen.map { $0.movesNewWindows.toggle() } }
            }
        }
        move.toolTip = L("Nye vinduer på fuld skærm-skærmen flyttes til din arbejdsskærm (kræver Tilgængelighed)", "New windows on the full screen display are moved to your work display (requires Accessibility)")
        menu.addItem(move)
    }

    /// Farve ▸ til temaet Flad. Altid aktiv: vælger man en farve, skifter temaet til Flad, så valget
    /// ses med det samme (en grå menu ville kræve to skridt og skjule, hvorfor den er grå).
    private func flatColorMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let isFlat = settings.theme == .flat
        for c in FlatColor.allCases {
            if c == .custom || c == FlatColor.allCases.dropFirst().first { m.addItem(.separator()) }
            let checked = isFlat && settings.flatColor == c
            let i: NSMenuItem
            if c == .custom {
                i = item(c.title, checked: checked) { [settings] in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { FlatColorPicker.shared.show(settings: settings) }
                    }
                }
                if settings.flatColor == .custom { i.image = Self.swatch(hex: settings.flatCustomHex) }
            } else {
                i = item(c.title, checked: checked) { [settings] in
                    settings.flatColor = c
                    settings.theme = .flat
                }
                if let hex = c.hex { i.image = Self.swatch(hex: hex) }
            }
            m.addItem(i)
        }
        return m
    }

    /// Lille rund farveprik (12 pt) til menupunkter.
    static func swatch(hex: String, diameter: CGFloat = 12) -> NSImage {
        let color = NSColor(hex: hex) ?? .gray
        return NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { r in
            let path = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    /// Lille, grå forklaring under et punkt (deaktiveret menupunkt).
    private func note(_ text: String) -> NSMenuItem {
        let i = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        i.isEnabled = false
        i.indentationLevel = 1
        i.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return i
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
        alert.messageText = L("Fjern Pladespiller fra skrivebordet?", "Remove Pladespiller from the desktop?")
        alert.informativeText = L("Den åbner ikke længere ved login.", "It will no longer open at login.")
        alert.addButton(withTitle: L("Fjern", "Remove"))
        alert.addButton(withTitle: L("Annuller", "Cancel")).keyEquivalent = "\u{1b}"
        alert.window.level = .modalPanel
        guard alert.runModal() == .alertFirstButtonReturn else {
            if let previous, previous != NSRunningApplication.current { previous.activate() }
            return
        }
        LoginItem.disable()
        NSApp.terminate(nil)
    }
}
