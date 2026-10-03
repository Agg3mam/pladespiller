import AppKit
import SwiftUI

/// Det kantløse vindue nede på skrivebordet. Ejes af Vindue-agenten.
final class WidgetPanel: NSPanel {
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Opretter panelet og holder SwiftUI-indholdet. Bølge 0: fast placering øverst til venstre.
final class WidgetPanelController {
    private let settings: Settings
    private let panel: WidgetPanel

    init<Content: View>(settings: Settings, @ViewBuilder content: () -> Content) {
        self.settings = settings
        let size = WidgetMetrics.windowSize(for: settings.size)
        panel = WidgetPanel(size: size)
        let host = NSHostingView(rootView: WidgetChrome(content: content()).environment(settings))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    func show() {
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: v.minX, y: v.maxY - size.height))
        }
        panel.orderFrontRegardless()
    }
}
