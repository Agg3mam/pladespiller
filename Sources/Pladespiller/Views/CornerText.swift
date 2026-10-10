import AppKit
import Observation
import SwiftUI

/// Farver til teksten der står direkte på pladespillerens krop (ikke på widgettens flade).
struct CornerColors: Equatable {
    var title: NSColor
    var secondary: NSColor
    /// Kroppen er lys (mørk tekst) – bruges til at vælge farveskema for evt. knapper på kroppen.
    var lightBody: Bool

    static func make(_ style: TurntableStyle) -> CornerColors {
        if let p = style.flatPalette {
            return CornerColors(title: p.titleColor, secondary: p.secondaryColor, lightBody: p.isLight)
        }
        let light: Bool = switch style.plinth {
        case .aluminium: true
        case let .matte(r, g, b): 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5
        default: false
        }
        return light
            ? CornerColors(title: NSColor(white: 0.08, alpha: 0.9), secondary: NSColor(white: 0, alpha: 0.5), lightBody: true)
            : CornerColors(title: NSColor(white: 1, alpha: 0.95), secondary: NSColor(white: 1, alpha: 0.6), lightBody: false)
    }
}

private struct TextTintKey: EnvironmentKey { static let defaultValue: NSColor? = nil }
private struct LyricsTransitionKey: EnvironmentKey { static let defaultValue: Double? = nil }

extension EnvironmentValues {
    /// Fast tekstfarve for titlen (fx på det flade temas krop). Nil = følg lys/mørk tilstand.
    var textTint: NSColor? {
        get { self[TextTintKey.self] }
        set { self[TextTintKey.self] = newValue }
    }
    /// Kun snapshots: tegn et linjeskift i sangteksten midt i overgangen (0...1).
    var lyricsTransition: Double? {
        get { self[LyricsTransitionKey.self] }
        set { self[LyricsTransitionKey.self] = newValue }
    }
}

/// Hjørnet med sangtekst – eller titel (fed) + kunstner (dæmpet) som på referencebilledet.
struct CornerText: View {
    enum Size { case small, medium, large }

    let np: NowPlaying?
    let lyrics: LyricsState
    let showLyrics: Bool
    let size: Size
    let colors: CornerColors
    let width: CGFloat

    @Environment(\.windowIsVisible) private var windowVisible

    var titleSize: CGFloat { size == .large ? 20 : 15 }
    var secondarySize: CGFloat { size == .large ? 14 : 12 }

    var body: some View {
        Group {
            if let np {
                if showLyrics, case .found(let l) = lyrics, l.trackKey == np.trackKey, !l.lines.isEmpty || l.instrumental {
                    LyricsView(np: np, lyrics: l, size: size, colors: colors, width: width)
                } else if size != .small {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: TrackStrings.title(np), size: titleSize, width: width, active: np.isPlaying && windowVisible,
                                    weight: .bold)
                            .padding(.leading, -Layout.leadingBearing(TrackStrings.title(np), font: .systemFont(ofSize: titleSize, weight: .bold)))
                            .environment(\.textTint, colors.title)
                            .probe("titel")
                        Text(TrackStrings.artist(np))
                            .font(.system(size: secondarySize, weight: .medium))
                            .foregroundStyle(Color(nsColor: colors.secondary))
                            .lineLimit(1)
                            .probe("kunstner")
                    }
                }
            } else if size != .small {
                Text(L("Intet spiller", "Nothing playing"))
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(Color(nsColor: colors.title).opacity(0.55))
                    .probe("titel")
            }
        }
        .frame(width: width, alignment: .bottomLeading)
    }
}

// MARK: - Sangtekst

/// Hvilken linje/hvilket ord der synges nu. Opdateres af én planlagt opgave ad gangen (vågner kun ved næste
/// linje- eller ordstart) – ingen opdatering pr. billede. Der er kun én widget, så tilstanden er fælles.
@Observable
final class LyricsClock {
    static let shared = LyricsClock()
    var trackKey = ""
    var lineIndex: Int?
    var wordIndex: Int?

    static func index(_ l: Lyrics, at position: TimeInterval) -> (line: Int?, word: Int?) {
        guard let li = l.lineIndex(at: position) else { return (nil, nil) }
        let words = l.lines[li].words
        let wi = words.isEmpty ? nil : words.lastIndex { $0.start <= position }
        return (li, wi)
    }

    /// Næste tidspunkt (position i sangen) hvor linje eller ord skifter.
    static func nextBoundary(_ l: Lyrics, after position: TimeInterval) -> TimeInterval? {
        var best: TimeInterval?
        if let next = l.lines.first(where: { $0.start > position })?.start { best = next }
        if let li = l.lineIndex(at: position), let w = l.lines[li].words.first(where: { $0.start > position })?.start {
            best = min(best ?? w, w)
        }
        return best
    }

    func set(_ key: String, _ idx: (line: Int?, word: Int?)) {
        if trackKey != key { trackKey = key }
        if lineIndex != idx.line { lineIndex = idx.line }
        if wordIndex != idx.word { wordIndex = idx.word }
    }

    /// Kører så længe der spilles og vinduet er synligt; afbrydes (task-id skifter) ved pause, spring, sangskift, occlusion.
    func run(np: NowPlaying, lyrics: Lyrics) async {
        while !Task.isCancelled {
            let pos = np.position(at: .now)
            set(np.trackKey, Self.index(lyrics, at: pos))
            guard np.isPlaying, let next = Self.nextBoundary(lyrics, after: pos) else { return }
            let wait = max(0.02, next - pos + 0.01)
            // Præcis opvågning: uden en lille tolerance må systemet samle vækninger og komme for sent.
            try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(10))
        }
    }
}

struct LyricsView: View {
    let np: NowPlaying
    let lyrics: Lyrics
    let size: CornerText.Size
    let colors: CornerColors
    let width: CGFloat
    /// Fuld skærm: skriften tegnes i denne størrelse (ikke forstørret som billede, så den står skarpt).
    var scale: CGFloat = 1

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.lyricsTransition) private var transition
    @Environment(\.windowIsVisible) private var windowVisible

    private var clock: LyricsClock { LyricsClock.shared }

    private var fontSize: CGFloat {
        switch size {
        case .small: 11 * scale
        case .medium: 14 * scale
        case .large: 19 * scale
        }
    }

    /// Linje/ord nu: live fra uret, i snapshots udregnet direkte af positionen.
    private var index: (line: Int?, word: Int?) {
        if snapshot != nil || clock.trackKey != np.trackKey {
            return LyricsClock.index(lyrics, at: np.position(at: snapshot != nil ? np.positionTimestamp : .now))
        }
        return (clock.lineIndex, clock.wordIndex)
    }

    var body: some View {
        let idx = index
        VStack(alignment: .leading, spacing: (size == .large ? 4 : 2) * scale) {
            ZStack(alignment: .bottomLeading) {
                if let p = transition, let li = idx.line, li > 0 {
                    // Snapshot af et linjeskift midt i overgangen (samme bevægelse som live)
                    let e = 1 - pow(1 - p, 3)                                   // ease-out
                    lineView(li - 1, word: Int.max).opacity(1 - e).offset(y: -e * 6 * scale)
                    lineView(li, word: idx.word).opacity(e).offset(y: (1 - e) * 8 * scale)
                } else {
                    lineView(idx.line, word: idx.word)
                        .id(idx.line ?? -1)
                        .transition(.asymmetric(insertion: .offset(y: 8 * scale).combined(with: .opacity),
                                                removal: .offset(y: -6 * scale).combined(with: .opacity)))
                }
            }
            .animation(.easeOut(duration: 0.35), value: idx.line)
            if size != .small, let next = nextLine(after: idx.line) {
                Text(next)
                    .font(.system(size: fontSize * 0.72, weight: .semibold))
                    .foregroundStyle(Color(nsColor: colors.secondary).opacity(0.75))
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.35), value: idx.line)
            }
        }
        .opacity(np.isPlaying ? 1 : 0.8)                                        // pause: står stille, svagt dæmpet
        .frame(width: width, alignment: .bottomLeading)
        .task(id: taskKey) {
            guard snapshot == nil, windowVisible else { return }
            await clock.run(np: np, lyrics: lyrics)
        }
        .probe("sangtekst")
    }

    private var taskKey: String {
        "\(np.trackKey)|\(np.isPlaying)|\(np.position)|\(np.positionTimestamp.timeIntervalSinceReferenceDate)|\(windowVisible)"
    }

    private func nextLine(after li: Int?) -> String? {
        let start = (li ?? -1) + 1
        guard start < lyrics.lines.count else { return nil }
        let t = lyrics.lines[start].text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    @ViewBuilder private func lineView(_ li: Int?, word: Int?) -> some View {
        let font = Font.system(size: fontSize, weight: .bold)
        if li == nil, !lyrics.instrumental {
            // Før første linje (intro): titlen i stedet for en enlig node.
            Text(TrackStrings.title(np))
                .font(font)
                .foregroundStyle(Color(nsColor: colors.title))
                .lineLimit(1)
                .truncationMode(.tail)
        } else if lyrics.instrumental || li == nil || lyrics.lines[li!].isInstrumental {
            Text("♪")
                .font(font)
                .foregroundStyle(Color(nsColor: colors.title).opacity(0.6))
        } else {
            let line = lyrics.lines[li!]
            Text(attributed(line, word: word))
                .font(font)
                .lineLimit(size == .small ? 1 : 2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ord-timing: de ord der er sunget står i fuld farve, resten svagere (roligt, uden "karaoke-blink").
    /// Uden ord-timing står hele linjen i fuld farve.
    private func attributed(_ line: Lyrics.Line, word: Int?) -> AttributedString {
        let full = Color(nsColor: colors.title)
        guard !line.words.isEmpty else {
            var a = AttributedString(line.text)
            a.foregroundColor = full
            return a
        }
        var out = AttributedString()
        for (i, w) in line.words.enumerated() {
            var part = AttributedString(w.text + (i < line.words.count - 1 && !w.text.hasSuffix(" ") ? " " : ""))
            let sung = word.map { i <= $0 } ?? false
            part.foregroundColor = sung ? full : full.opacity(0.42)
            out += part
        }
        return out
    }
}
