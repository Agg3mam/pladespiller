import AppKit
import SwiftUI

/// Svag "landingsplads" der viser, hvor widgetten falder på plads, mens man trækker.
/// Et separat, klik-gennemsigtigt panel på samme niveau, lagt lige under widgetten.
final class LandingShadow {
    private let panel: NSPanel
    private let host: NSHostingView<LandingShape>

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = WidgetMetrics.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        host = NSHostingView(rootView: LandingShape())
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func show(at frame: CGRect, below window: NSWindow) {
        panel.appearance = window.appearance
        panel.setFrame(frame, display: true)
        panel.order(.below, relativeTo: window.windowNumber)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func move(to frame: CGRect) {
        guard frame != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

private struct LandingShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .padding(WidgetMetrics.windowInset)
    }
}
