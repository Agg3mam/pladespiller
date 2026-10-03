import SwiftUI

/// Widgettens "skal": baggrund, hjørner og kant. Ejes af Vindue-agenten.
///
/// Matcher brugerens Apple-widgets (målt 2026-10-03, Ikon- og widgetstil = Mørk, fuld farve):
/// - Flade indrykket 8 pt, radius 28 pt continuous, ingen skygge.
/// - Uigennemsigtig baggrund. Mørk: svag lodret gradient som Kalender (≈ #262626 → #111111).
/// - Lys kant der er stærkest på top- og bundkanten og forsvinder ned langs siderne
///   (målt på Status, bg 13: yderste px +77, næste +44, tredje +15; midt på siderne: 0).
/// - Klar/Tonet stil: Liquid Glass i stedet for den uigennemsigtige flade.
struct WidgetChrome<Content: View>: View {
    @Environment(Settings.self) private var settings
    @Environment(WidgetStyle.self) private var style: WidgetStyle?   // valgfri, så snapshots virker uden
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
        let size = WidgetMetrics.bodySize(for: settings.size)
        Group {
            if style?.material == .glass {
                content
                    .frame(width: size.width, height: size.height)
                    .clipShape(shape)
                    .glassEffect(.clear, in: shape)
            } else {
                content
                    .frame(width: size.width, height: size.height)
                    .background(WidgetBackground(scheme: colorScheme))
                    .clipShape(shape)
            }
        }
        .overlay(WidgetRim(height: size.height))
        .padding(WidgetMetrics.windowInset)
    }
}

/// Den uigennemsigtige flade bag indholdet.
struct WidgetBackground: View {
    let scheme: ColorScheme

    var body: some View {
        switch scheme {
        case .dark:
            LinearGradient(colors: [Color(white: 0.145), Color(white: 0.066)],
                           startPoint: .top, endPoint: .bottom)
        default:
            LinearGradient(colors: [Color(white: 1.0), Color(white: 0.955)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Den svage lyse kant: tre lag (0,5/1/1,5 pt) giver faldet 0,30 → 0,17 → 0,06 udefra og ind,
/// maskeret så den kun ses langs top og bund og toner ud over de øverste/nederste ≈40 pt.
struct WidgetRim: View {
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
        let fade: CGFloat = 40
        let f = min(fade / max(height, 1), 0.5)
        ZStack {
            shape.strokeBorder(Color.white.opacity(0.04), lineWidth: 1.5)
            shape.strokeBorder(Color.white.opacity(0.11), lineWidth: 1.0)
            shape.strokeBorder(Color.white.opacity(0.17), lineWidth: 0.5)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.6), location: f * 0.2),
                .init(color: .white.opacity(0.2), location: f * 0.5),
                .init(color: .white.opacity(0.07), location: f * 0.75),
                .init(color: .clear, location: f),
                .init(color: .clear, location: 1 - f),
                .init(color: .white.opacity(0.07), location: 1 - f * 0.75),
                .init(color: .white.opacity(0.2), location: 1 - f * 0.5),
                .init(color: .white.opacity(0.6), location: 1 - f * 0.2),
                .init(color: .white, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}
