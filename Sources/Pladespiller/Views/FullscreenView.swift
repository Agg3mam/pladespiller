import AppKit
import SwiftUI

/// Indholdet i fuld skærm (`settings.fullscreenLayout`). Ejes af Grafik-agenten.
///
/// - Kroppens farve/materiale fylder hele skærmen (én `TurntableView` over hele vinduet, så der ingen samlinger er);
///   dækket (plade + arm) placeres efter layoutet. Rotation og arm kører i Core Animation som i widgetten.
/// - Riller og etiket tegnes i skærmens fulde opløsning én gang pr. størrelse; bløde flader i 1x. Store billeder
///   frigives når fuld skærm lukkes.
/// - Alle mål skalerer med vinduets højde (`unit` = højde / 1440), så det ser ens ud på 1080, 1440 og ultrawide.
private struct FullscreenCoverStripKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Dækket over menulinjen på fuld skærm-skærmen: viser kun pladespilleren (ingen tekst), så den flugter med
    /// fuld skærm nedenunder, uden at sangteksten kører to gange.
    var fullscreenCoverStrip: Bool {
        get { self[FullscreenCoverStripKey.self] }
        set { self[FullscreenCoverStripKey.self] = newValue }
    }
}

struct FullscreenView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.snapshotLyrics) private var snapshotLyrics
    @Environment(\.snapshotAccessProblem) private var snapshotProblem
    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.fullscreenCoverStrip) private var coverStrip

    private var np: NowPlaying? { store.current }
    private var lyrics: LyricsState { snapshotLyrics ?? store.lyrics }
    private var problem: SourceAccessProblem? { snapshotProblem ?? store.accessProblem }
    private var style: TurntableStyle {
        TurntableStyle.make(theme: settings.theme, artwork: np?.artwork, flatColor: settings.flatColor, customHex: settings.flatCustomHex,
                            deckDetails: true)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let colors = CornerColors.make(style)
            ZStack(alignment: .topLeading) {
                turntable(size, deck: Self.deck(for: settings.fullscreenLayout, size: size, flat: settings.theme == .flat))
                if !coverStrip {
                Group {
                    switch settings.fullscreenLayout {
                    case .lyrics: lyricsSide(size, colors: colors)
                    case .turntable: bottomCorner(size, colors: colors)
                    }
                }
                .allowsHitTesting(false)
                if let problem {
                    StatusCapsule(text: problem.message, warning: true, action: { store.openAutomationSettings() },
                                  scale: Self.unit(size) * 2.6)
                        .padding(Self.unit(size) * 48)
                }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.windowIsVisible, snapshot != nil || WindowVisibility.shared.isVisible)
        }
        .background { if snapshot == nil { WindowVisibilityReader() } }
        .onDisappear { if !coverStrip { TurntableImages.purgeLarge() } }     // frigiv de store billeder når fuld skærm lukkes
    }

    static func unit(_ size: CGSize) -> CGFloat { max(0.5, size.height / 1440) }

    private func turntable(_ size: CGSize, deck: CGRect) -> some View {
        TurntableView(size: size, cornerRadius: 0, deck: deck, theme: settings.theme,
                      flatColor: settings.flatColor, flatCustomHex: settings.flatCustomHex, nowPlaying: np, dim: 0,
                      speed: settings.spinSpeed, scrubbing: false, deckDetails: true,
                      onArmClick: { store.playPause() }, onRecordClick: { store.openSourceApp() },
                      onSpeedClick: { settings.spinSpeed = $0 })
    }

    // MARK: Placering af pladespilleren

    /// Dækket: den synlige masse (pladens venstrekant → armens leje/fordybning) centreres i sit felt; hele pladen synlig.
    static func deck(for layout: FullscreenLayout, size: CGSize, flat: Bool) -> CGRect {
        func mass(_ d: CGFloat) -> (minX: CGFloat, maxX: CGFloat) {
            let g = TurntableGeometry(size: CGSize(width: d * 3, height: d * 3), cornerRadius: 0,
                                      deck: CGRect(x: 0, y: 0, width: d, height: d), flat: flat)
            let right = g.pivot.x + g.basePlateRadius
            return (g.center.x - g.platterRadius, right)
        }
        let W = size.width, H = size.height
        switch layout {
        case .lyrics:
            // venstre ~45 % af bredden, lodret centreret
            let field = W * 0.47
            let probe = mass(1000)
            let massPerD = (probe.maxX - probe.minX) / 1000
            let d = min(field * 0.92 / massPerD, H * 0.80 / 0.744)
            let m = mass(d)
            let x = field / 2 + W * 0.03 - (m.minX + m.maxX) / 2
            return CGRect(x: x.rounded(), y: ((H - d) / 2).rounded(), width: d.rounded(), height: d.rounded())
        case .turntable:
            // stor og centreret (pladen ca. 70 % af højden), lidt over midten så teksten nederst har plads
            let probe = mass(1000)
            let massPerD = (probe.maxX - probe.minX) / 1000
            let d = min(H * 0.70 / 0.744, W * 0.9 / massPerD)
            let m = mass(d)
            let x = W / 2 - (m.minX + m.maxX) / 2
            return CGRect(x: x.rounded(), y: (H * 0.46 - d / 2).rounded(), width: d.rounded(), height: d.rounded())
        }
    }

    // MARK: Med sangtekst: højre side

    private func lyricsSide(_ size: CGSize, colors: CornerColors) -> some View {
        let u = Self.unit(size)
        let x = size.width * 0.54
        let width = size.width * 0.42
        return ZStack(alignment: .topLeading) {
            if let np {
                if case .found(let l) = lyrics, settings.showLyrics, l.trackKey == np.trackKey, !l.lines.isEmpty || l.instrumental {
                    // Sangteksten holder sig i sit eget felt og fader blødt ud foroven og forneden, så de kommende
                    // linjer aldrig løber ned i titel og kunstner nederst (altid mindst ca. 12 % af højden luft).
                    FullscreenLyrics(np: np, lyrics: l, unit: u, width: width, colors: colors)
                        .frame(width: width, height: size.height * 0.74, alignment: .leading)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                   .init(color: .black, location: 0.74), .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .offset(x: x, y: size.height * 0.06)
                    meta(np, unit: u, colors: colors, large: false)
                        .frame(width: width, alignment: .leading)
                        .offset(x: x, y: size.height - u * 120)
                } else {
                    // Ingen tekst: stor titel, kunstner og album, centreret i højre side
                    meta(np, unit: u, colors: colors, large: true)
                        .frame(width: width, height: size.height, alignment: .leading)
                        .offset(x: x)
                }
            } else {
                Text(L("Intet spiller", "Nothing playing"))
                    .font(.system(size: u * 72, weight: .bold))
                    .foregroundStyle(Color(nsColor: colors.title).opacity(0.55))
                    .frame(width: width, height: size.height, alignment: .leading)
                    .offset(x: x)
            }
        }
        .opacity(np?.isPlaying == false ? 0.8 : 1)            // pause: alt står stille, teksten dæmpes svagt
    }

    private func meta(_ np: NowPlaying, unit u: CGFloat, colors: CornerColors, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: u * (large ? 10 : 4)) {
            Text(TrackStrings.title(np))
                .font(.system(size: u * (large ? 76 : 40), weight: .bold))
                .foregroundStyle(Color(nsColor: colors.title))
                .lineLimit(large ? 3 : 1)
            Text(large ? TrackStrings.artist(np) : [TrackStrings.artist(np), TrackStrings.album(np)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: u * (large ? 40 : 28), weight: .semibold))
                .foregroundStyle(Color(nsColor: colors.secondary))
                .lineLimit(1)
            if large, let album = TrackStrings.album(np) {
                Text(album)
                    .font(.system(size: u * 30, weight: .medium))
                    .foregroundStyle(Color(nsColor: colors.secondary).opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    // MARK: Kun pladespiller: diskret nederst til venstre (som hjørnet i widgetten, bare større)

    private func bottomCorner(_ size: CGSize, colors: CornerColors) -> some View {
        let u = Self.unit(size)
        let pad = u * 64
        // Teksten flugter med pladens venstre kant (ikke skærmens hjørne), så den hører til pladespilleren.
        let deck = Self.deck(for: .turntable, size: size, flat: settings.theme == .flat)
        let left = max(pad, (deck.minX + deck.width * 0.048).rounded())
        let width = min(size.width * 0.6, size.width - left - pad)
        return VStack(alignment: .leading, spacing: u * 16) {
            if let np {
                if settings.showLyrics, case .found(let l) = lyrics, l.trackKey == np.trackKey {
                    LyricsView(np: np, lyrics: l, size: .large, colors: colors, width: width, scale: u * 2.4)
                    Text("\(TrackStrings.title(np)) · \(TrackStrings.artist(np))")
                        .font(.system(size: u * 28, weight: .semibold))
                        .foregroundStyle(Color(nsColor: colors.secondary))
                        .lineLimit(1)
                } else {
                    Text(TrackStrings.title(np))
                        .font(.system(size: u * 54, weight: .bold))
                        .foregroundStyle(Color(nsColor: colors.title))
                        .lineLimit(1)
                    Text(TrackStrings.artist(np))
                        .font(.system(size: u * 32, weight: .semibold))
                        .foregroundStyle(Color(nsColor: colors.secondary))
                        .lineLimit(1)
                }
            } else {
                Text(L("Intet spiller", "Nothing playing"))
                    .font(.system(size: u * 54, weight: .bold))
                    .foregroundStyle(Color(nsColor: colors.title).opacity(0.55))
            }
        }
        .opacity(np?.isPlaying == false ? 0.8 : 1)
        .frame(width: size.width - left - pad, height: size.height - pad * 2, alignment: .bottomLeading)
        .offset(x: left, y: pad)
    }
}

// MARK: - Sangtekst i Apple Music-stil

/// Listen af linjer: den aktuelle stor og fed i fuld farve, tidligere linjer svagere over, de kommende 2–4 under.
/// Positionen er ét kontinuert tal (`position` = aktuel linje); ved linjeskift animeres det én gang (0,5 s ease-out),
/// så listen glider op. Ingen arbejde mellem skiftene. Ord-fremhævning når `words` findes.
struct FullscreenLyrics: View {
    let np: NowPlaying
    let lyrics: Lyrics
    let unit: CGFloat
    let width: CGFloat
    let colors: CornerColors

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.lyricsTransition) private var transition
    @Environment(\.windowIsVisible) private var windowVisible

    private var clock: LyricsClock { LyricsClock.shared }

    private var index: (line: Int?, word: Int?) {
        if snapshot != nil || clock.trackKey != np.trackKey {
            return LyricsClock.index(lyrics, at: np.position(at: snapshot != nil ? np.positionTimestamp : .now))
        }
        return (clock.lineIndex, clock.wordIndex)
    }

    var body: some View {
        let idx = index
        let current = Double(idx.line ?? -1)
        let position: Double = {
            guard let p = transition, idx.line != nil else { return current }
            let e = 1 - pow(1 - p, 3)
            return current - 1 + e
        }()
        LyricsStack(position: position, current: idx.line, word: idx.word, lyrics: lyrics, fontSize: unit * 76,
                    width: width, colors: colors)
            .animation(.easeOut(duration: 0.5), value: idx.line)
            .task(id: "\(np.trackKey)|\(np.isPlaying)|\(np.position)|\(np.positionTimestamp.timeIntervalSinceReferenceDate)|\(windowVisible)") {
                guard snapshot == nil, windowVisible else { return }
                await clock.run(np: np, lyrics: lyrics)
            }
    }
}

private struct LyricsStack: View, Animatable {
    var position: Double
    let current: Int?
    let word: Int?
    let lyrics: Lyrics
    let fontSize: CGFloat
    let width: CGFloat
    let colors: CornerColors

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    private var lineHeight: CGFloat { fontSize * 1.18 }
    private var gap: CGFloat { fontSize * 0.55 }

    /// Antal tekstlinjer en sangtekstlinje fylder (højst 2), målt med skriften.
    private func rows(_ i: Int) -> CGFloat {
        guard i >= 0, i < lyrics.lines.count, !lyrics.lines[i].isInstrumental else { return 1 }
        let w = (lyrics.lines[i].text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)]).width
        return min(2, max(1, ceil(w / max(width, 1))))
    }

    /// Lodret midte for linje i når linje c er den aktuelle (heltal). Højderne følger linjernes skala, så en aktuel linje
    /// på to linjer skubber naboerne væk i stedet for at overlappe.
    private func center(_ i: Int, current c: Int) -> CGFloat {
        func h(_ j: Int) -> CGFloat { rows(j) * lineHeight * scale(Double(j - c)) }
        var y: CGFloat = 0
        if i > c { for j in c..<i { y += h(j) / 2 + gap + h(j + 1) / 2 } }
        if i < c { for j in stride(from: c, to: i, by: -1) { y -= h(j) / 2 + gap + h(j - 1) / 2 } }
        return y
    }

    /// Mellem to heltalspositioner glider alt jævnt (positionen animeres én gang pr. linjeskift).
    private func offset(_ i: Int) -> CGFloat {
        let lo = Int(position.rounded(.down)), t = CGFloat(position - Double(lo))
        let a = center(i, current: lo), b = center(i, current: lo + 1)
        return a + (b - a) * t
    }

    var body: some View {
        let base = Int(position.rounded(.down))
        ZStack(alignment: .leading) {
            ForEach(max(-1, base - 3)...min(lyrics.lines.count - 1, base + 5), id: \.self) { i in
                let d = Double(i) - position
                line(i)
                    .frame(width: width, alignment: .leading)
                    .scaleEffect(scale(d), anchor: .leading)
                    .opacity(opacity(d))
                    .offset(y: offset(i))
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private func scale(_ d: Double) -> CGFloat { CGFloat(1 - 0.36 * min(abs(d), 1)) }

    private func opacity(_ d: Double) -> Double {
        if d < 0 {
            // tidligere linjer: 1 → 0,32 for den forrige, derefter ud mod 0 opad
            // (mindst ca. 40 % for de nærmeste, så de kan læses på alle farver)
            if d > -1 { return 1 + (0.42 - 1) * -d }
            return max(0, 0.42 * (1 - (-d - 1) / 1.6))
        }
        let future = [1.0, 0.58, 0.46, 0.36, 0.24, 0.0]
        let i = min(Int(d), future.count - 2), f = d - Double(i)
        return future[i] + (future[i + 1] - future[i]) * f
    }

    @ViewBuilder private func line(_ i: Int) -> some View {
        let font = Font.system(size: fontSize, weight: .bold)
        if i < 0 || lyrics.instrumental || lyrics.lines[i].isInstrumental {
            Text("♪").font(font).foregroundStyle(Color(nsColor: colors.title))
        } else {
            Text(attributed(lyrics.lines[i], word: i == current ? word : (i < (current ?? -1) ? Int.max : nil),
                            highlight: i == current))
                .font(font)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func attributed(_ line: Lyrics.Line, word: Int?, highlight: Bool) -> AttributedString {
        let full = Color(nsColor: colors.title)
        guard highlight, !line.words.isEmpty else {
            var a = AttributedString(line.text)
            a.foregroundColor = full
            return a
        }
        var out = AttributedString()
        for (i, w) in line.words.enumerated() {
            var part = AttributedString(w.text + (i < line.words.count - 1 && !w.text.hasSuffix(" ") ? " " : ""))
            part.foregroundColor = (word.map { i <= $0 } ?? false) ? full : full.opacity(0.4)
            out += part
        }
        return out
    }
}
