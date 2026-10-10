import AppKit
import Observation
import SwiftUI

/// Læser om et vindue er synligt (occlusion), så tidslabel, rulletekst og sangtekst kan stoppe når det er dækket
/// (QA N9). Ingen polling: kun NSWindow.didChangeOcclusionStateNotification.
/// Hvert vindue har sin EGEN tilstand: widgetten bruger `shared`, fuld skærm sin egen. (Før delte de én, så en
/// dækket widget kunne stoppe sangteksten på fuld skærm og omvendt.)
@Observable
final class WindowVisibility {
    /// Widgettens vindue.
    static let shared = WindowVisibility()
    /// Fuld skærm-vinduet.
    static let fullscreen = WindowVisibility()
    var isVisible = true
}

struct WindowVisibilityReader: NSViewRepresentable {
    var target: WindowVisibility = .shared

    func makeNSView(context: Context) -> ReaderView {
        let v = ReaderView()
        let target = target
        v.onChange = { visible in
            if target.isVisible != visible { target.isVisible = visible }
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
