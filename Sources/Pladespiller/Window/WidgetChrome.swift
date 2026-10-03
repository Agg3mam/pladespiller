import SwiftUI

/// Widgettens "skal": baggrund, hjørner, kant og (senere) falmet look.
/// Indholdet (pladespilleren) får hele den synlige flade. Ejes af Vindue-agenten.
struct WidgetChrome<Content: View>: View {
    @Environment(Settings.self) private var settings
    let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
        let body = WidgetMetrics.bodySize(for: settings.size)
        content
            .frame(width: body.width, height: body.height)
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
            .padding(WidgetMetrics.windowInset)
    }
}
