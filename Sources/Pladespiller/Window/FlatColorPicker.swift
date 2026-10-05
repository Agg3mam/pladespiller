import AppKit

/// "Vælg farve…": NSColorPanel for temaet Flad. Den løbende farve gemmes som sRGB-hex i
/// `settings.flatCustomHex`, og `flatColor` sættes til `.custom` (og temaet til Flad).
/// En baggrundsapp skal aktiveres, for at panelet kommer frem; når panelet lukkes, får det
/// forrige program fokus igen (som ved "Fjern widget").
final class FlatColorPicker: NSObject {
    static let shared = FlatColorPicker()

    private weak var settings: Settings?
    private var previousApp: NSRunningApplication?
    private var closeObserver: NSObjectProtocol?

    func show(settings: Settings) {
        self.settings = settings
        let front = NSWorkspace.shared.frontmostApplication
        if front != NSRunningApplication.current { previousApp = front }
        NSApp.activate()

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.color = NSColor(hex: settings.flatCustomHex) ?? .systemYellow
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.title = "Farve til Flad"
        panel.level = .floating

        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.panelClosed() }
            }
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let settings, let hex = sender.color.srgbHex else { return }
        if settings.flatCustomHex != hex { settings.flatCustomHex = hex }
        if settings.flatColor != .custom { settings.flatColor = .custom }
        if settings.theme != .flat { settings.theme = .flat }
    }

    private func panelClosed() {
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }
}

extension NSColor {
    /// "F2B705" / "#F2B705" → sRGB-farve.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// sRGB-hex uden "#", fx "F2B705".
    var srgbHex: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        func b(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }
}
