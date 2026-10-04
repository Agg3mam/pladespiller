import AppKit
import Observation
import SwiftUI

/// Læser om widgettens vindue er synligt (occlusion), så tidslabel og rulletekst kan stoppe når det er dækket (QA N9).
/// Ingen polling: kun NSWindow.didChangeOcclusionStateNotification.
/// Der er kun ét widgetvindue pr. app (én kopi kører ad gangen), så tilstanden er fælles.
@Observable
final class WindowVisibility {
    static let shared = WindowVisibility()
    var isVisible = true
}

struct WindowVisibilityReader: NSViewRepresentable {
    func makeNSView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.onChange = { visible in
            if WindowVisibility.shared.isVisible != visible { WindowVisibility.shared.isVisible = visible }
        }
        return v
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private weak var observed: NSWindow?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            if let observed { center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: observed) }
            observed = window
            guard let window else { return }
            center.addObserver(self, selector: #selector(changed), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            changed()
        }

        @objc private func changed() {
            guard let window else { return }
            // Et vindue der endnu ikke er vist regnes som synligt (som TurntableNSView).
            let visible = window.occlusionState.contains(.visible) || !window.isVisible
            DispatchQueue.main.async { [weak self] in self?.onChange(visible) }
        }
    }
}
