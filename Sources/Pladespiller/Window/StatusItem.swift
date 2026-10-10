import AppKit

/// Et lille ikon i menulinjen med de samme indstillinger som højrekliksmenuen (størrelse, tema, farve,
/// hastighed, fuld skærm osv.). Menuen bygges frisk hver gang den åbnes, så flueben altid er aktuelle.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    /// Egen menu-instans (ikke widgettens), så de to menuer ikke rydder hinandens handlinger.
    private let widgetMenu: WidgetMenu
    private let menu = NSMenu()

    init(settings: Settings, fullscreen: FullscreenController?, playerWindow: PlayerWindowController? = nil) {
        widgetMenu = WidgetMenu(settings: settings)
        widgetMenu.fullscreen = fullscreen
        widgetMenu.playerWindow = playerWindow
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = Self.icon
            button.toolTip = "Pladespiller"
            button.setAccessibilityLabel(L("Pladespiller-indstillinger", "Pladespiller settings"))
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = widgetMenu.build()
        for i in fresh.items {
            fresh.removeItem(i)
            menu.addItem(i)
        }
    }

    /// Plade set ovenfra med arm, som template-billede (macOS farver det sort/hvidt efter menulinjen).
    static let icon: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let record = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 3.5, width: 12, height: 12))
            record.lineWidth = 1.4
            record.stroke()
            NSBezierPath(ovalIn: NSRect(x: 5.5, y: 7.5, width: 4, height: 4)).fill()     // etiket
            let arm = NSBezierPath()
            arm.move(to: NSPoint(x: 15.5, y: 2.5))
            arm.line(to: NSPoint(x: 15.5, y: 9.5))
            arm.line(to: NSPoint(x: 11.8, y: 13.2))
            arm.lineWidth = 1.4
            arm.lineCapStyle = .round
            arm.lineJoinStyle = .round
            arm.stroke()
            NSBezierPath(ovalIn: NSRect(x: 14, y: 1, width: 3, height: 3)).fill()       // armens leje
            return true
        }
        img.isTemplate = true
        return img
    }()
}
