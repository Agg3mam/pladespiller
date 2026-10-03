import SwiftUI

/// Lader SwiftUI-indhold (fx tonearmen) sige "dette træk er mit", så vinduet ikke flytter sig.
///
/// Brug i Views:  `Arm().claimsWidgetDrag()`
/// eller sæt `widgetDragClaim?.isClaimed = true` selv i en egen gesture.
/// Panelet nulstiller kravet ved hvert mouseDown.
final class WidgetDragClaim {
    var isClaimed = false
}

private struct WidgetDragClaimKey: EnvironmentKey {
    static let defaultValue: WidgetDragClaim? = nil
}

extension EnvironmentValues {
    // Ingen @Entry: makro-plugins findes ikke med kun Command Line Tools.
    var widgetDragClaim: WidgetDragClaim? {
        get { self[WidgetDragClaimKey.self] }
        set { self[WidgetDragClaimKey.self] = newValue }
    }
}

extension View {
    /// Træk der starter i dette view flytter ikke widgetten.
    func claimsWidgetDrag() -> some View { modifier(ClaimsWidgetDragModifier()) }
}

private struct ClaimsWidgetDragModifier: ViewModifier {
    @Environment(\.widgetDragClaim) private var claim

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { _ in claim?.isClaimed = true }
                .onEnded { _ in claim?.isClaimed = false }
        )
    }
}
