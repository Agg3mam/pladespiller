import AppKit
import SwiftUI

/// Fuld skærm på en (helst ekstra) skærm. Ejes af Vindue-agenten. Pladsholder.
final class FullscreenController {
    private let settings: Settings
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init<Content: View>(settings: Settings, @ViewBuilder content: @escaping () -> Content) {
        self.settings = settings
        self.makeContent = { AnyView(content()) }
    }

    var isShowing: Bool { window != nil }
    func toggle() { isShowing ? hide() : show() }
    func show() {}
    func hide() { window?.close(); window = nil }
}
