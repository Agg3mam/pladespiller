import Foundation
import Observation
import SwiftUI

/// Hvordan widgetten præsenteres lige nu. Ejes (værdierne) af Vindue-agenten, som opretter den i
/// `WidgetPanelController` og lægger den i environment. Grafik-agenten læser den.
@Observable
final class WidgetPresentation {
    /// 0 = fuld farve, 1 = helt dæmpet (falmet look). Skifter blødt over `WidgetMetrics.dimTransition`
    /// — Vindue-agenten sætter målværdien; Grafik-agenten animerer sit lagtræ derhen.
    var dimAmount: Double = 0
    /// Musen er over widgetten (bruges fx til afspil/pause ved hover i lille størrelse).
    var isHovering = false
}

private struct WidgetPresentationKey: EnvironmentKey {
    static let defaultValue = WidgetPresentation()
}

extension EnvironmentValues {
    var widgetPresentation: WidgetPresentation {
        get { self[WidgetPresentationKey.self] }
        set { self[WidgetPresentationKey.self] = newValue }
    }
}

/// Et adgangsproblem hos en kilde, fx at brugeren ikke har givet lov til at styre Spotify.
struct SourceAccessProblem: Equatable {
    var bundleID: String
    /// Kort dansk tekst til widgetten, fx "Giv adgang til Spotify i Systemindstillinger".
    var message: String
}
