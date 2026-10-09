import SwiftUI

/// Indholdet i widgetten for lille/mellem/stor. Ejes af Grafik-agenten.
/// Fladen er `WidgetMetrics.bodySize(for:)`; baggrund/glas tegnes af `WidgetChrome`.
///
/// Layoutet følger et fast gitter (`Layout`): indhold 16 pt fra kanten, kroppen 8 pt fra kanten med
/// koncentriske hjørner, 12 pt mellem krop og tekst. Titlens versalhøjde ligger 8 pt under kroppens overkant,
/// knaprækken 8 pt over dens underkant. Målt og bevist i `snapshots/layout-tjek.txt`.
///
/// Klik: armen = afspil/pause, pladen = åbn musikappen, knapperne = forrige/afspil-pause/næste.
struct WidgetView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.widgetPresentation) private var presentation

    var body: some View {
        let body = WidgetMetrics.bodySize(for: settings.size)
        Group {
            // "Står alene" (standard): kun pladespilleren + hjørnet med sangtekst/titel – i alle temaer.
            switch settings.size {
            // Pladespilleren fylder altid hele widgetten (ingen ramme om kroppen), i alle temaer.
            case .small:
                standaloneSmall(body)
            case .medium:
                if standalone { standaloneMedium(body) } else { fullMedium(body) }
            case .large:
                if standalone { standaloneLarge(body) } else { large(body) }
            }
        }
        .frame(width: body.width, height: body.height)
        .background { if liveSnapshot == nil { WindowVisibilityReader() } }   // kun live (ImageRenderer kan ikke tegne NSViews)
        .environment(\.windowIsVisible, windowVisible)
    }

    @Environment(\.snapshotAccessProblem) private var snapshotProblem
    @Environment(\.turntableSnapshot) private var liveSnapshot
    /// Vinduet er synligt (ikke dækket). Tid, fremdrift og rulletekst kører kun når det er sandt (QA N9).
    private var windowVisible: Bool { WindowVisibility.shared.isVisible }
    private var np: NowPlaying? { store.current }
    private var problem: SourceAccessProblem? { snapshotProblem ?? store.accessProblem }
    private var dim: Double { presentation.dimAmount }

    private var standalone: Bool { !settings.showControls }
    private var flat: Bool { settings.theme == .flat }
    private var style: TurntableStyle {
        TurntableStyle.make(theme: settings.theme, artwork: np?.artwork, flatColor: settings.flatColor, customHex: settings.flatCustomHex)
    }
    @Environment(\.snapshotLyrics) private var snapshotLyrics
    private var lyrics: LyricsState { snapshotLyrics ?? store.lyrics }

    private func turntable(_ size: CGSize, radius: CGFloat = Layout.objectRadius, deck: CGRect? = nil) -> some View {
        TurntableView(size: size, cornerRadius: radius, deck: deck, theme: settings.theme,
                      flatColor: settings.flatColor, flatCustomHex: settings.flatCustomHex, nowPlaying: np, dim: dim,
                      speed: settings.spinSpeed, scrubbing: ScrubState.shared.fraction != nil,
                      onArmClick: { store.playPause() }, onRecordClick: { store.openSourceApp() },
                      onSpeedClick: { settings.spinSpeed = $0 })
            .probe("krop")
    }

    /// SwiftUI-delen (tekst og knapper) dæmpes på samme måde som lagtræet.
    private func dimmed(_ v: some View) -> some View {
        v.saturation(1 - TurntableLayer.dimSaturationLoss * dim)
            .opacity(1 - (1 - TurntableLayer.dimOpacity) * dim)
            .animation(.easeInOut(duration: WidgetMetrics.dimTransition), value: dim)
    }

    private var actions: TrackActions {
        TrackActions(previous: { store.previousTrack() }, playPause: { store.playPause() }, next: { store.nextTrack() },
                     openApp: { store.openSourceApp() }, openSettings: { store.openAutomationSettings() },
                     seek: { store.seek(to: $0) })
    }

    /// Versalhøjden af titlen skal ligge præcis her (y fra widgettens top).
    private func titleTop(_ capY: CGFloat) -> CGFloat { capY - Layout.capInset(Layout.titleFont()) }

    // MARK: Lille: kun pladespilleren; afspil/pause når musen er over

    private func small(_ body: CGSize) -> some View {
        let side = body.height - Layout.objectInset * 2
        return turntable(CGSize(width: side, height: side))
            .overlay(alignment: .topLeading) {
                // Manglende adgang: øverst til venstre (dækker hverken etiket, arm eller 33/45-knapper), højst 2 linjer.
                if let problem {
                    StatusCapsule(text: problem.message, warning: true, action: actions.openSettings)
                        .padding(Layout.padding - Layout.objectInset)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Group {
                    if np == nil, problem == nil {
                        StatusCapsule(text: "Intet spiller", warning: false)
                    } else if problem == nil, presentation.isHovering, let np {
                        HoverPlayButton(isPlaying: np.isPlaying, action: actions.playPause)
                            .transition(.opacity)
                    }
                }
                .padding(Layout.padding - Layout.objectInset)
                .animation(.easeInOut(duration: 0.2), value: presentation.isHovering)
            }
            .padding(Layout.objectInset)
    }

    // MARK: Står alene: pladespilleren fylder hele widgetten; hjørnet viser sangtekst eller titel + kunstner

    /// Dækket (plade + arm) når pladespilleren står alene. Pladen er HELT synlig: 16 pt til kanten foroven og til venstre
    /// (Lille: lidt mindre, så der er plads til én tekstlinje forneden). Armen står til højre.
    static func standaloneDeck(_ size: WidgetSize) -> CGRect {
        let edge: CGFloat = 0.048, top: CGFloat = 0.128            // pladens yderkant i dækket (0,42 − 0,372 / 0,5 − 0,372)
        switch size {
        case .large:
            let d: CGFloat = 330
            return CGRect(x: Layout.padding - edge * d, y: Layout.padding - top * d, width: d, height: d)
        case .medium:
            let d = (WidgetMetrics.bodySize(for: .medium).height - Layout.padding * 2) / 0.744
            return CGRect(x: Layout.padding - edge * d, y: Layout.padding - top * d, width: d, height: d)
        case .small:
            let d: CGFloat = 156
            return CGRect(x: 2, y: -6, width: d, height: d)
        }
    }

    /// Hjørnefeltet (x, bund, bredde) når pladespilleren står alene.
    static func cornerRect(_ size: WidgetSize) -> (x: CGFloat, bottom: CGFloat, width: CGFloat) {
        let body = WidgetMetrics.bodySize(for: size)
        switch size {
        case .large:
            return (Layout.padding, body.height - Layout.padding, body.width - Layout.padding * 2)
        case .medium:
            // til højre for armens leje, nederst
            let g = TurntableGeometry(size: body, cornerRadius: WidgetMetrics.cornerRadius, deck: standaloneDeck(.medium), flat: true)
            // luft til armens fod: 12 pt + 6 pt, så lejet aldrig rører titlen
            let x = (g.pivot.x + g.basePlateRadius + Layout.gap + 6).rounded()
            return (x, body.height - Layout.padding, body.width - Layout.padding - x)
        case .small:
            return (12, body.height - 12, body.width - 24)
        }
    }

    private func standaloneBody(_ size: WidgetSize, _ body: CGSize, corner: CornerText.Size) -> some View {
        let c = Self.cornerRect(size)
        return ZStack(alignment: .topLeading) {
            turntable(body, radius: WidgetMetrics.cornerRadius, deck: Self.standaloneDeck(size))
            dimmed(
                CornerText(np: np, lyrics: lyrics, showLyrics: settings.showLyrics, size: corner,
                           colors: CornerColors.make(style), width: c.width)
                    .frame(width: c.width, height: c.bottom, alignment: .bottomLeading)
                    .offset(x: c.x)
                    .allowsHitTesting(false)
            )
        }
        .frame(width: body.width, height: body.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if let problem {
                StatusCapsule(text: problem.message, warning: true, action: actions.openSettings).padding(Layout.padding)
            }
        }
    }

    private func standaloneLarge(_ body: CGSize) -> some View { standaloneBody(.large, body, corner: .large) }
    private func standaloneMedium(_ body: CGSize) -> some View { standaloneBody(.medium, body, corner: .medium) }

    private func standaloneSmall(_ body: CGSize) -> some View {
        standaloneBody(.small, body, corner: .small)
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if np == nil, problem == nil {
                        StatusCapsule(text: "Intet spiller", warning: false)
                    } else if problem == nil, presentation.isHovering, let np {
                        HoverPlayButton(isPlaying: np.isPlaying, action: actions.playPause).transition(.opacity)
                    }
                }
                .padding(10)
                .animation(.easeInOut(duration: 0.2), value: presentation.isHovering)
            }
    }

    // MARK: Mellem med knapper: kroppen fylder widgetten; kolonnen står direkte på kroppen (alle temaer)

    /// Titel, kunstner og album øverst med fremdrift og tider lige under; knapperne nederst.
    private func fullMedium(_ body: CGSize) -> some View {
        let c = Self.cornerRect(.medium)
        let colors = CornerColors.make(style)
        return ZStack(alignment: .topLeading) {
            turntable(body, radius: WidgetMetrics.cornerRadius, deck: Self.standaloneDeck(.medium))
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    TrackText(np: np, problem: problem, width: c.width, showAlbum: true, albumInline: true, actions: actions)
                    if let np {
                        ProgressRow(np: np, onSeek: actions.seek).padding(.top, 10)
                        Spacer(minLength: 0)
                        TransportRow(isPlaying: np.isPlaying, spread: true, actions: actions)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, titleTop(Layout.padding))
                .padding(.bottom, Layout.padding)
                .frame(width: c.width, height: body.height, alignment: .topLeading)
                .environment(\.colorScheme, colors.lightBody ? .light : .dark)
                .offset(x: c.x)
            )
        }
        .frame(width: body.width, height: body.height, alignment: .topLeading)
    }

    // MARK: Stor med knapper: pladespilleren fylder widgetten; en smal stribe nederst (knapper ved hover)

    /// Stribens indryk og indvendige luft. Hjørnet er koncentrisk med widgetten (28 − 8 = 20).
    static let panelInset = Layout.objectInset
    static let panelPadding: CGFloat = 12

    /// Dækket når knapperne er vist: lidt mindre end når pladespilleren står alene, så striben kun lige
    /// rører pladens underkant.
    static func largeDeck(_ body: CGSize) -> CGRect {
        let edge: CGFloat = 0.048, top: CGFloat = 0.128, d: CGFloat = 312
        return CGRect(x: Layout.padding - edge * d, y: Layout.padding - top * d, width: d, height: d)
    }

    private func large(_ body: CGSize) -> some View {
        let inner = body.width - Self.panelInset * 2 - Self.panelPadding * 2
        let colors = CornerColors.make(style)
        let hovering = presentation.isHovering
        return ZStack(alignment: .bottom) {
            turntable(body, radius: WidgetMetrics.cornerRadius, deck: Self.largeDeck(body))
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    if let np {
                        TrackText(np: np, problem: problem, width: inner, showAlbum: true, albumInline: true, actions: actions)
                        ProgressRow(np: np, onSeek: actions.seek).padding(.top, 8)
                        if hovering {
                            TransportRow(isPlaying: np.isPlaying, spread: false, actions: actions)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        TrackText(np: nil, problem: problem, width: inner, centered: true, actions: actions)
                        if problem == nil {
                            Text("Start musik i Spotify eller Musik")
                                .font(.system(size: Layout.tertiarySize))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 3)
                        }
                    }
                }
                .padding(.top, np == nil ? Self.panelPadding : titleTop(Self.panelPadding))
                .padding([.horizontal, .bottom], Self.panelPadding)
                .frame(width: body.width - Self.panelInset * 2, alignment: .topLeading)
                .background { InfoPanelBackground(tint: Self.panelTint(style), light: colors.lightBody).probe("panel") }
                .environment(\.colorScheme, colors.lightBody ? .light : .dark)
                .padding(Self.panelInset)
                .animation(.easeInOut(duration: 0.2), value: hovering)
            )
        }
        .frame(width: body.width, height: body.height, alignment: .topLeading)
    }

    /// Stribens farve: kroppens egen farve (træets gennemsnit, metallets grå, Flads farve).
    static func panelTint(_ style: TurntableStyle) -> SIMD3<Float> {
        style.flatPalette?.body ?? PlinthRenderer.solidColor(style.plinth)
    }
}

/// Stribens flade: tonet glas i kroppens egen farve – mørk tone på mørke kroppe, lys tone på lyse – så den hører
/// til temaet i stedet for at ligne et indsat ark. Tæt nok til at teksten altid kan læses.
struct InfoPanelBackground: View {
    var tint: SIMD3<Float>
    var light: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.objectRadius, style: .continuous)
        let t = light ? tint + (SIMD3<Float>(1, 1, 1) - tint) * 0.72 : tint * 0.32
        shape
            .fill(Color(.sRGB, red: Double(t.x), green: Double(t.y), blue: Double(t.z)).opacity(light ? 0.9 : 0.86))
            .overlay(shape.strokeBorder(light ? Color.black.opacity(0.06) : Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(light ? 0.16 : 0.32), radius: 6, y: 2)
    }
}

struct TrackActions {
    var previous: () -> Void
    var playPause: () -> Void
    var next: () -> Void
    var openApp: () -> Void
    var openSettings: () -> Void
    var seek: (TimeInterval) -> Void
}

// MARK: - Tekst

/// Titel (semibold 15, rulletekst), kunstner (.secondary 13) med kildeappens ikon inline foran, evt. album.
/// Ved manglende tilladelse vises beskeden i stedet for kunstneren.
struct TrackText: View {
    let np: NowPlaying?
    let problem: SourceAccessProblem?
    let width: CGFloat
    var showAlbum = false
    var albumInline = false
    var centered = false
    let actions: TrackActions
    @Environment(\.windowIsVisible) private var windowVisible

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: Layout.lineGap) {
            if let np {
                title(TrackStrings.title(np), active: np.isPlaying && windowVisible)
                if let problem {
                    ProblemText(message: problem.message, size: Layout.secondarySize - 1, action: actions.openSettings)
                        .layoutPriority(1)
                } else {
                    artistLine(np)
                    if showAlbum, !albumInline, let album = TrackStrings.album(np) {
                        Text(album)
                            .font(.system(size: Layout.tertiarySize))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .probe("album")
                    }
                }
            } else {
                Text("Intet spiller")
                    .font(.system(size: Layout.titleSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, centered ? 0 : -Layout.leadingBearing("Intet", font: Layout.titleFont()))
                    .probe("titel")
                if let problem {
                    ProblemText(message: problem.message, size: Layout.secondarySize - 1, action: actions.openSettings).layoutPriority(1)
                }
            }
        }
        .frame(width: width, alignment: centered ? .center : .leading)
    }

    private func title(_ text: String, active: Bool) -> some View {
        MarqueeText(text: text, size: Layout.titleSize, width: width, active: active)
            .padding(.leading, -Layout.leadingBearing(text, font: Layout.titleFont()))
            .frame(maxWidth: .infinity, alignment: .leading)
            .probe("titel")
    }

    private func artistLine(_ np: NowPlaying) -> some View {
        var text = TrackStrings.artist(np)
        if albumInline, showAlbum, let album = TrackStrings.album(np) { text += " · " + album }
        return HStack(spacing: 5) {
            SourceIcon(bundleID: np.sourceAppBundleID, size: Layout.sourceIconSize, action: actions.openApp)
                .probe("ikon")
            Text(text)
                .font(.system(size: Layout.secondarySize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .probe("kunstner")
        }
    }
}

struct ProblemText: View {
    let message: String
    let size: CGFloat
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) { label }
            .buttonStyle(WidgetButtonStyle())
    }

    private var label: some View {
        Label {
            Text(message)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.system(size: size))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Knapper

/// Forrige · afspil/pause · næste. Ikonerne er beskåret til deres synlige blæk (`Glyph`), så rækkens visuelle
/// kanter er rammens kanter. `spread`: første ikon flugter med kolonnens venstrekant, sidste med højrekanten.
struct TransportRow: View {
    let isPlaying: Bool
    let spread: Bool
    let actions: TrackActions

    var body: some View {
        HStack(spacing: spread ? 0 : 30) {
            glyphButton("backward.fill", label: "Forrige", action: actions.previous).probe("forrige")
            if spread { Spacer(minLength: 0) }
            Button(action: actions.playPause) {
                ZStack {
                    Circle().fill(.primary.opacity(0.11))
                    GlyphView(name: isPlaying ? "pause.fill" : "play.fill", height: Layout.playGlyphHeight)
                        .offset(x: isPlaying ? 0 : 1)        // optisk centrering af trekanten
                }
                .frame(width: Layout.playDiameter, height: Layout.playDiameter)
                .contentShape(Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Afspil")
            .probe("afspil")
            if spread { Spacer(minLength: 0) }
            glyphButton("forward.fill", label: "Næste", action: actions.next).probe("næste")
        }
        .buttonStyle(WidgetButtonStyle())
        .foregroundStyle(.primary)
        .frame(height: Layout.playDiameter)
    }

    private func glyphButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlyphView(name: name, height: Layout.skipGlyphHeight)
                .padding(10).contentShape(Rectangle()).padding(-10)     // større klikflade, samme layout
        }
        .accessibilityLabel(label)
    }
}

/// Ingen baggrund; trykket ned = lidt mindre og svagere (som widgetknapper).
struct WidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 0.9)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Afspil/pause ved hover i lille størrelse: lille mørk cirkel nede i hjørnet (dækker ikke etiketten).
struct HoverPlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlyphView(name: isPlaying ? "pause.fill" : "play.fill", height: 11)
                .offset(x: isPlaying ? 0 : 1)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(WidgetButtonStyle())
        .accessibilityLabel(isPlaying ? "Pause" : "Afspil")
    }
}

struct StatusCapsule: View {
    let text: String
    let warning: Bool
    var action: () -> Void = {}
    /// Fuld skærm: tegnes i denne størrelse i stedet for at blive forstørret (skarp tekst).
    var scale: CGFloat = 1
    var body: some View {
        if warning {
            Button(action: action) { capsule }.buttonStyle(WidgetButtonStyle())
        } else {
            capsule
        }
    }

    private var capsule: some View {
        HStack(spacing: 4 * scale) {
            if warning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(text).lineLimit(2).multilineTextAlignment(.leading)
        }
        .font(.system(size: 10 * scale, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 7 * scale).padding(.vertical, 4 * scale)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
        .frame(maxWidth: 120 * scale, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Kildeappens ikon (Spotify/Musik), lille og inline foran kunstneren; klik åbner appen. Reserve: en node.
struct SourceIcon: View {
    let bundleID: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let icon = SourceApp.icon(for: bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                GlyphView(name: "music.note", height: size * 0.8)
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .accessibilityLabel("Åbn \(SourceApp.name(for: bundleID) ?? "musikappen")")
    }
}

// MARK: - Indstillinger for titler

enum TitleStyle: String, CaseIterable {
    case ellipsis, marquee
}

private struct TitleStyleKey: EnvironmentKey { static let defaultValue: TitleStyle = .marquee }
private struct MarqueePhaseKey: EnvironmentKey { static let defaultValue: Double? = nil }
private struct SnapshotProblemKey: EnvironmentKey { static let defaultValue: SourceAccessProblem? = nil }
private struct SnapshotLyricsKey: EnvironmentKey { static let defaultValue: LyricsState? = nil }
private struct WindowIsVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// Hvordan lange titler vises. Brugerens valg: rulletekst.
    var titleStyle: TitleStyle {
        get { self[TitleStyleKey.self] }
        set { self[TitleStyleKey.self] = newValue }
    }
    /// Widgettens vindue er synligt (ikke dækket af andre vinduer).
    var windowIsVisible: Bool {
        get { self[WindowIsVisibleKey.self] }
        set { self[WindowIsVisibleKey.self] = newValue }
    }
    /// Kun snapshots: sangtekst-tilstand at vise.
    var snapshotLyrics: LyricsState? {
        get { self[SnapshotLyricsKey.self] }
        set { self[SnapshotLyricsKey.self] = newValue }
    }
    /// Kun snapshots: et adgangsproblem at vise (butikken sætter det selv live).
    var snapshotAccessProblem: SourceAccessProblem? {
        get { self[SnapshotProblemKey.self] }
        set { self[SnapshotProblemKey.self] = newValue }
    }
    /// Kun snapshots: fast fase (0...1) i rulleteksten.
    var marqueePhase: Double? {
        get { self[MarqueePhaseKey.self] }
        set { self[MarqueePhaseKey.self] = newValue }
    }
}
