import SwiftUI

/// Indholdet i widgetten for lille/mellem/stor. Ejes af Grafik-agenten.
/// Fladen er `WidgetMetrics.bodySize(for:)`; baggrund/glas tegnes af `WidgetChrome`.
struct WidgetView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store

    /// Afstand fra widgettens kant til pladespilleren; hjørnerne bliver koncentriske med widgettens (28 − 8 = 20).
    static let inset: CGFloat = 8
    static var innerRadius: CGFloat { WidgetMetrics.cornerRadius - inset }

    var body: some View {
        let body = WidgetMetrics.bodySize(for: settings.size)
        Group {
            switch settings.size {
            case .small: small(body)
            case .medium: medium(body)
            case .large: large(body)
            }
        }
        .frame(width: body.width, height: body.height)
    }

    private var np: NowPlaying? { store.current }

    private func turntable(_ size: CGSize) -> some View {
        TurntableView(size: size, cornerRadius: Self.innerRadius, theme: settings.theme, nowPlaying: np)
    }

    // MARK: Lille: kun pladespilleren

    private func small(_ body: CGSize) -> some View {
        let side = body.height - Self.inset * 2
        return turntable(CGSize(width: side, height: side))
            .overlay(alignment: .bottomLeading) {
                if np == nil {
                    Text("Intet spiller")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
            .padding(Self.inset)
    }

    // MARK: Mellem: pladespiller til venstre, titel og kunstner til højre (foreløbigt)

    private func medium(_ body: CGSize) -> some View {
        let side = body.height - Self.inset * 2
        let textWidth = body.width - Self.inset - side - 12 - 14
        return HStack(spacing: 12) {
            turntable(CGSize(width: side, height: side))
            TrackText(np: np, width: textWidth, titleSize: 15, artistSize: 13, titleLines: 2)
                .frame(width: textWidth, alignment: .leading)
        }
        .padding(.leading, Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Stor: pladespilleren øverst, tekst under (foreløbigt)

    private func large(_ body: CGSize) -> some View {
        let w = body.width - Self.inset * 2
        let h: CGFloat = 244
        return VStack(alignment: .leading, spacing: 0) {
            turntable(CGSize(width: w, height: h))
            TrackText(np: np, width: w - 16, titleSize: 17, artistSize: 14, titleLines: 1)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(Self.inset)
    }
}

/// Titel (fed), kunstner (dæmpet) og en lille status ved pause. Farver følger lys/mørk tilstand.
struct TrackText: View {
    let np: NowPlaying?
    let width: CGFloat
    let titleSize: CGFloat
    let artistSize: CGFloat
    let titleLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let np {
                TitleText(text: np.title, size: titleSize, width: width, lines: titleLines, active: np.isPlaying)
                Text(np.artist)
                    .font(.system(size: artistSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !np.isPlaying {
                    Label("På pause", systemImage: "pause.fill")
                        .font(.system(size: artistSize - 2, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .padding(.top, 2)
                }
            } else {
                Text("Intet spiller")
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lange titler: "…" eller rulletekst

enum TitleStyle: String, CaseIterable {
    case ellipsis, marquee
}

private struct TitleStyleKey: EnvironmentKey { static let defaultValue: TitleStyle = .ellipsis }
private struct MarqueePhaseKey: EnvironmentKey { static let defaultValue: Double? = nil }

extension EnvironmentValues {
    /// Hvordan lange titler vises. Standard "…" (afventer brugerens valg).
    var titleStyle: TitleStyle {
        get { self[TitleStyleKey.self] }
        set { self[TitleStyleKey.self] = newValue }
    }
    /// Kun snapshots: fast fase (0...1) i rulleteksten.
    var marqueePhase: Double? {
        get { self[MarqueePhaseKey.self] }
        set { self[MarqueePhaseKey.self] = newValue }
    }
}

struct TitleText: View {
    let text: String
    let size: CGFloat
    let width: CGFloat
    let lines: Int
    let active: Bool

    @Environment(\.titleStyle) private var style
    @Environment(\.marqueePhase) private var fixedPhase

    private var font: Font { .system(size: size, weight: .bold) }
    private var textWidth: CGFloat {
        let ns = NSFont.systemFont(ofSize: size, weight: .bold)
        return ceil((text as NSString).size(withAttributes: [.font: ns]).width)
    }

    var body: some View {
        switch style {
        case .ellipsis:
            Text(text).font(font).lineLimit(lines).truncationMode(.tail)
        case .marquee:
            if textWidth <= width {
                Text(text).font(font).lineLimit(1)
            } else if let fixedPhase {
                marquee(phase: fixedPhase)
            } else {
                // Kører kun mens der spilles (koster lidt CPU mens teksten ruller).
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { ctx in
                    marquee(phase: Self.phase(at: ctx.date, distance: textWidth + Self.gap))
                }
            }
        }
    }

    static let gap: CGFloat = 32
    static let speed: Double = 28     // pt/s
    static let hold: Double = 2.5     // pause ved start

    static func phase(at date: Date, distance: CGFloat) -> Double {
        let scroll = Double(distance) / speed
        let cycle = hold + scroll
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return t < hold ? 0 : (t - hold) / scroll
    }

    private func marquee(phase: Double) -> some View {
        let distance = textWidth + Self.gap
        return HStack(spacing: Self.gap) {
            Text(text).font(font).fixedSize()
            Text(text).font(font).fixedSize()
        }
        .offset(x: -distance * phase)
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask(
            LinearGradient(stops: [.init(color: phase > 0 ? .clear : .black, location: 0), .init(color: .black, location: 0.04),
                                   .init(color: .black, location: 0.90), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}
