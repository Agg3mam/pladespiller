import Observation
import SwiftUI

/// Fælles tilstand for spoling (der er kun én widget). Bruges også af tid og arm, så de følger musen under træk.
@Observable
final class ScrubState {
    static let shared = ScrubState()
    /// Fremdrift 0...1 mens der trækkes/klikkes (nil = intet træk).
    var fraction: Double?
    /// Hvilken sang trækket gælder (så et sangskift midt i et træk ikke viser forkert tid).
    var trackKey: String?
    /// Musen er over linjen.
    var hovering = false

    func fraction(for np: NowPlaying) -> Double? { trackKey == np.trackKey ? fraction : nil }
}

/// Kun snapshots: vis linjen som om musen er over den / der trækkes.
struct SeekPreview: Equatable {
    var hover = true
    var fraction: Double? = nil
}

private struct SeekPreviewKey: EnvironmentKey { static let defaultValue: SeekPreview? = nil }

extension EnvironmentValues {
    var seekPreview: SeekPreview? {
        get { self[SeekPreviewKey.self] }
        set { self[SeekPreviewKey.self] = newValue }
    }
}

/// Fremdriftslinje man kan spole på (som Apples afspillerlinjer).
///
/// - Klik: spol dertil. Træk: scrub – linje og tid følger musen, `onSeek` kaldes løbende og én gang til ved slip.
/// - Klikfladen er 18 pt høj (overlay), så layoutet ikke flytter sig; linjen selv er 3 pt og bliver 5 pt med en
///   lille knap (thumb), når musen er over den eller der trækkes.
/// - Et træk på linjen flytter aldrig vinduet: kravet (`widgetDragClaim`) sættes allerede ved mouseDown.
/// - Uden varighed (radio) kan linjen ikke bruges, og der vises ingen knap.
struct SeekBar: View {
    let np: NowPlaying
    let onSeek: (TimeInterval) -> Void

    static let hitHeight: CGFloat = 18
    static let activeHeight: CGFloat = 5
    static let thumbDiameter: CGFloat = 11

    @Environment(\.widgetDragClaim) private var claim
    @Environment(\.seekPreview) private var preview
    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme

    private var scrub: ScrubState { ScrubState.shared }
    private var canSeek: Bool { np.duration > 0 }
    private var dragFraction: Double? { preview?.fraction ?? scrub.fraction(for: np) }
    private var hovering: Bool { preview?.hover ?? scrub.hovering }
    private var active: Bool { canSeek && (hovering || dragFraction != nil) }

    var body: some View {
        ZStack {
            if active {
                if let f = dragFraction {
                    ActiveLine(fraction: f, dark: scheme == .dark)
                } else if snapshot != nil {
                    ActiveLine(fraction: np.progress(at: np.positionTimestamp), dark: scheme == .dark)
                } else {
                    // Kun mens musen er over linjen: knappen følger afspilningen to gange i sekundet.
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        ActiveLine(fraction: np.progress(at: ctx.date), dark: scheme == .dark)
                    }
                }
            } else {
                ProgressLine(np: np)
            }
        }
        .frame(height: Layout.progressHeight)
        .overlay { if canSeek { hitArea } }
        .animation(.easeOut(duration: 0.12), value: active)
        .accessibilityElement()
        .accessibilityLabel(L("Fremdrift", "Progress"))
        .accessibilityValue("\(formatTime(np.position(at: .now))) \(L("af", "of")) \(formatTime(np.duration))")
        .accessibilityAdjustableAction { direction in
            guard canSeek else { return }
            let step: TimeInterval = direction == .increment ? 10 : -10
            onSeek(min(max(0, np.position(at: .now) + step), np.duration))
        }
    }

    private var hitArea: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active: if !scrub.hovering { scrub.hovering = true }
                    case .ended: scrub.hovering = false
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            claim?.isClaimed = true                 // ved mouseDown: vinduet må ikke flytte sig
                            let f = fraction(value.location.x, width: geo.size.width)
                            scrub.trackKey = np.trackKey
                            scrub.fraction = f
                            onSeek(f * np.duration)
                        }
                        .onEnded { value in
                            let f = fraction(value.location.x, width: geo.size.width)
                            onSeek(f * np.duration)                 // den endelige position
                            scrub.fraction = nil
                            claim?.isClaimed = false
                        }
                )
        }
        .frame(height: Self.hitHeight)
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }
}

/// Den tykke linje med knap (hover/træk). Ligger centreret over den tynde linjes plads, så intet flytter sig.
private struct ActiveLine: View {
    let fraction: Double
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = SeekBar.activeHeight, d = SeekBar.thumbDiameter
            let x = w * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: dark ? 1 : 0).opacity(dark ? 0.24 : 0.15))
                    .frame(width: w, height: h)
                Capsule().fill(Color(white: dark ? 1 : 0).opacity(dark ? 0.92 : 0.80))
                    .frame(width: max(h, x), height: h)
                Circle()
                    .fill(dark ? Color.white : Color(white: 0.99))
                    .overlay(Circle().strokeBorder(Color.black.opacity(dark ? 0 : 0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: d, height: d)
                    .offset(x: x - d / 2)
            }
            .frame(width: w, height: geo.size.height)
        }
    }
}
