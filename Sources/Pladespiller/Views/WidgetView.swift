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
    @Environment(\.largeLayout) private var largeLayout

    var body: some View {
        let body = WidgetMetrics.bodySize(for: settings.size)
        Group {
            switch settings.size {
            case .small: small(body)
            case .medium: medium(body)
            case .large:
                switch largeLayout {
                case .classic: largeClassic(body)
                case .wood: largeWood(body)
                case .centered: largeCentered(body)
                case .cropped: largeCropped(body)
                }
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

    private func turntable(_ size: CGSize, radius: CGFloat = Layout.objectRadius, deck: CGRect? = nil) -> some View {
        TurntableView(size: size, cornerRadius: radius, deck: deck, theme: settings.theme, nowPlaying: np, dim: dim,
                      speed: settings.spinSpeed,
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
                     openApp: { store.openSourceApp() }, openSettings: { store.openAutomationSettings() })
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

    // MARK: Mellem: krop til venstre; titel, kunstner, album, fremdrift og knapper i en kolonne på gitteret

    static func mediumColumn(_ body: CGSize) -> (x: CGFloat, width: CGFloat) {
        let side = body.height - Layout.objectInset * 2
        let x = Layout.objectInset + side + Layout.gap
        return (x, body.width - Layout.padding - x)
    }

    private func medium(_ body: CGSize) -> some View {
        let side = body.height - Layout.objectInset * 2
        let col = Self.mediumColumn(body)
        return HStack(alignment: .top, spacing: Layout.gap) {
            turntable(CGSize(width: side, height: side))
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    TrackText(np: np, problem: problem, width: col.width, showAlbum: true, actions: actions)
                    Spacer(minLength: 0)
                    if let np {
                        ProgressLine(np: np).probe("fremdrift")
                            .padding(.bottom, Layout.progressToButtons)
                        TransportRow(isPlaying: np.isPlaying, spread: true, actions: actions)
                    }
                }
                // Titlens versalhøjde = kroppens top + 8; knaprækkens bund = kroppens bund − 8.
                .padding(.top, titleTop(Layout.padding) - Layout.objectInset)
                .padding(.bottom, Layout.padding - Layout.objectInset)
                .frame(width: col.width, height: side, alignment: .topLeading)
            )
        }
        .padding(Layout.objectInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Stor (standard indtil brugeren har valgt): krop øverst, tekst, fremdrift og knapper under

    static let largeClassicDeckHeight: CGFloat = 208

    private func largeClassic(_ body: CGSize) -> some View {
        let w = body.width - Layout.objectInset * 2
        let h = Self.largeClassicDeckHeight
        let textWidth = body.width - Layout.padding * 2
        return VStack(alignment: .leading, spacing: 0) {
            turntable(CGSize(width: w, height: h))
                .padding(Layout.objectInset)
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    TrackText(np: np, problem: problem, width: textWidth, showAlbum: true, albumInline: true, actions: actions)
                        .padding(.top, titleTop(Layout.gap) - Layout.objectInset)   // versalhøjde = krop bund + 12
                    Spacer(minLength: 0)
                    if let np {
                        ProgressRow(np: np).padding(.bottom, Layout.progressToButtons)
                        TransportRow(isPlaying: np.isPlaying, spread: false, actions: actions)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Layout.padding)
                .padding(.bottom, Layout.padding)
            )
        }
    }

    // MARK: Forslag A "Helt træ": kroppen fylder hele widgetten; mørk infobjælke nederst

    private func largeWood(_ body: CGSize) -> some View {
        let panelHeight: CGFloat = 116
        let deckSide = body.height - panelHeight - Layout.objectInset * 3
        let deck = CGRect(x: (body.width - deckSide) / 2 - 6, y: Layout.objectInset, width: deckSide, height: deckSide)
        return ZStack(alignment: .bottom) {
            turntable(body, radius: WidgetMetrics.cornerRadius, deck: deck)
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    TrackText(np: np, problem: problem, width: body.width - Layout.padding * 2, showAlbum: true, albumInline: true,
                              actions: actions)
                        .padding(.top, titleTop(Layout.padding) - Layout.objectInset)
                    Spacer(minLength: 0)
                    if let np {
                        ProgressRow(np: np, light: true).padding(.bottom, Layout.progressToButtons)
                        TransportRow(isPlaying: np.isPlaying, spread: false, actions: actions).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Layout.padding - Layout.objectInset)
                .padding(.bottom, Layout.padding - Layout.objectInset)
                .frame(width: body.width - Layout.objectInset * 2, height: panelHeight, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: Layout.objectRadius, style: .continuous)
                        .fill(Color.black.opacity(0.52))
                        .overlay(RoundedRectangle(cornerRadius: Layout.objectRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                        .probe("panel")
                }
                .environment(\.colorScheme, .dark)
                .padding(Layout.objectInset)
            )
        }
    }

    // MARK: Forslag B "Centreret": kvadratisk pladespiller øverst, alt centreret under (som Apples Musik-widget)

    private func largeCentered(_ body: CGSize) -> some View {
        let side: CGFloat = 196
        return VStack(spacing: 0) {
            turntable(CGSize(width: side, height: side), radius: WidgetMetrics.cornerRadius - Layout.padding)
                .padding(.top, Layout.padding)
            dimmed(
                VStack(spacing: 0) {
                    TrackText(np: np, problem: problem, width: body.width - Layout.padding * 2, showAlbum: false, centered: true,
                              actions: actions)
                        .padding(.top, titleTop(Layout.gap))
                    Spacer(minLength: 0)
                    if let np {
                        ProgressRow(np: np).padding(.bottom, Layout.progressToButtons)
                        TransportRow(isPlaying: np.isPlaying, spread: false, actions: actions)
                    }
                }
                .padding(.horizontal, Layout.padding)
                .padding(.bottom, Layout.padding)
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Forslag C "Beskåret": en stor pladespiller fylder venstre side og skæres af widgettens kant; én kolonne til højre

    static let croppedSide: CGFloat = 328
    static var croppedOrigin: CGPoint { CGPoint(x: -146, y: Layout.objectInset) }
    static var croppedColumn: (x: CGFloat, width: CGFloat) {
        let x = croppedOrigin.x + croppedSide + Layout.gap
        return (x, WidgetMetrics.bodySize(for: .large).width - Layout.padding - x)
    }

    private func largeCropped(_ body: CGSize) -> some View {
        let side = Self.croppedSide, o = Self.croppedOrigin
        let col = Self.croppedColumn
        return ZStack(alignment: .topLeading) {
            turntable(CGSize(width: side, height: side))
                .offset(x: o.x, y: o.y)
            dimmed(
                VStack(alignment: .leading, spacing: 0) {
                    TrackText(np: np, problem: problem, width: col.width, showAlbum: true, twoLineTitle: true, actions: actions)
                    // Coveret som et pladeomslag i kolonnen (pladen ligger på pladespilleren ved siden af).
                    if let art = np?.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: col.width, height: col.width)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            .padding(.top, Layout.gap)
                            .probe("cover")
                    }
                    Spacer(minLength: 0)
                    if let np {
                        ProgressRow(np: np).padding(.bottom, Layout.progressToButtons)
                        TransportRow(isPlaying: np.isPlaying, spread: true, actions: actions)
                    }
                }
                .padding(.top, titleTop(Layout.padding))
                .padding(.bottom, Layout.padding)
                .frame(width: col.width, height: body.height, alignment: .topLeading)
                .offset(x: col.x)
            )
        }
        .frame(width: body.width, height: body.height, alignment: .topLeading)
        .clipped()
    }
}

/// Midlertidig: forslag til Stor, så brugeren kan vælge. Standard = nuværende (poleret) layout.
enum LargeLayout: String, CaseIterable {
    case classic, wood, centered, cropped
    var title: String {
        switch self {
        case .classic: "Nuværende"
        case .wood: "A · Helt træ"
        case .centered: "B · Centreret"
        case .cropped: "C · Plade + cover"
        }
    }
}

struct TrackActions {
    var previous: () -> Void
    var playPause: () -> Void
    var next: () -> Void
    var openApp: () -> Void
    var openSettings: () -> Void
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
    var twoLineTitle = false
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

    @ViewBuilder private func title(_ text: String, active: Bool) -> some View {
        if twoLineTitle {
            Text(text)
                .font(.system(size: Layout.titleSize + 2, weight: .semibold))
                .padding(.leading, -Layout.leadingBearing(text, font: .systemFont(ofSize: Layout.titleSize + 2, weight: .semibold)))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .probe("titel")
        } else {
            MarqueeText(text: text, size: Layout.titleSize, width: width, active: active)
                .padding(.leading, centered ? 0 : -Layout.leadingBearing(text, font: Layout.titleFont()))
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .probe("titel")
        }
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
    var body: some View {
        if warning {
            Button(action: action) { capsule }.buttonStyle(WidgetButtonStyle())
        } else {
            capsule
        }
    }

    private var capsule: some View {
        HStack(spacing: 4) {
            if warning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(text).lineLimit(2).multilineTextAlignment(.leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .frame(maxWidth: 120, alignment: .leading)
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
private struct WindowIsVisibleKey: EnvironmentKey { static let defaultValue = true }
private struct LargeLayoutKey: EnvironmentKey { static let defaultValue: LargeLayout = .classic }

extension EnvironmentValues {
    /// Hvordan lange titler vises. Brugerens valg: rulletekst.
    var titleStyle: TitleStyle {
        get { self[TitleStyleKey.self] }
        set { self[TitleStyleKey.self] = newValue }
    }
    /// Midlertidigt: hvilket forslag til Stor der vises (standard = nuværende).
    var largeLayout: LargeLayout {
        get { self[LargeLayoutKey.self] }
        set { self[LargeLayoutKey.self] = newValue }
    }
    /// Widgettens vindue er synligt (ikke dækket af andre vinduer).
    var windowIsVisible: Bool {
        get { self[WindowIsVisibleKey.self] }
        set { self[WindowIsVisibleKey.self] = newValue }
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
