import SwiftUI

/// Indholdet i widgetten for lille/mellem/stor. Ejes af Grafik-agenten.
/// Fladen er `WidgetMetrics.bodySize(for:)`; baggrund/glas tegnes af `WidgetChrome`.
///
/// Klik: armen = afspil/pause, pladen = åbn musikappen, knapperne = forrige/afspil-pause/næste.
/// Træk over 4 pt tages af panelet (og bliver aldrig til et klik).
struct WidgetView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.widgetPresentation) private var presentation

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
        .background { if liveSnapshot == nil { WindowVisibilityReader() } }   // kun live (ImageRenderer kan ikke tegne NSViews)
        .environment(\.windowIsVisible, windowVisible)
    }

    @Environment(\.snapshotAccessProblem) private var snapshotProblem
    @Environment(\.turntableSnapshot) private var liveSnapshot
    /// Vinduet er synligt (ikke dækket). Tid og rulletekst kører kun når det er sandt (QA N9).
    private var windowVisible: Bool { WindowVisibility.shared.isVisible }
    private var np: NowPlaying? { store.current }
    private var problem: SourceAccessProblem? { snapshotProblem ?? store.accessProblem }
    private var dim: Double { presentation.dimAmount }

    private func turntable(_ size: CGSize) -> some View {
        TurntableView(size: size, cornerRadius: Self.innerRadius, theme: settings.theme, nowPlaying: np, dim: dim,
                      onArmClick: { store.playPause() }, onRecordClick: { store.openSourceApp() })
    }

    /// SwiftUI-delen (tekst og knapper) dæmpes på samme måde som lagtræet.
    private func dimmed(_ v: some View) -> some View {
        v.saturation(1 - TurntableLayer.dimSaturationLoss * dim)
            .opacity(1 - (1 - TurntableLayer.dimOpacity) * dim)
            .animation(.easeInOut(duration: WidgetMetrics.dimTransition), value: dim)
    }

    // MARK: Lille: kun pladespilleren; afspil/pause når musen er over

    private func small(_ body: CGSize) -> some View {
        let side = body.height - Self.inset * 2
        return turntable(CGSize(width: side, height: side))
            .overlay(alignment: .topLeading) {
                // Manglende adgang: øverst til venstre (dækker hverken etiket, arm eller 33/45-knapper), højst 2 linjer.
                if let problem {
                    StatusCapsule(text: problem.message, warning: true) { store.openAutomationSettings() }
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Group {
                    if np == nil, problem == nil {
                        StatusCapsule(text: "Intet spiller", warning: false)
                    } else if problem == nil, presentation.isHovering, let np {
                        HoverPlayButton(isPlaying: np.isPlaying) { store.playPause() }
                            .transition(.opacity)
                    }
                }
                .padding(8)
                .animation(.easeInOut(duration: 0.2), value: presentation.isHovering)
            }
            .padding(Self.inset)
    }

    // MARK: Mellem: pladespiller til venstre; titel, kunstner, kildeapp og knapper til højre

    private func medium(_ body: CGSize) -> some View {
        let side = body.height - Self.inset * 2
        let textWidth = body.width - Self.inset - side - 14 - 14
        return HStack(spacing: 14) {
            turntable(CGSize(width: side, height: side))
            dimmed(
                VStack(alignment: .leading, spacing: 3) {
                    TrackHeader(np: np, problem: problem, width: textWidth, titleSize: 15, artistSize: 13, showAlbum: false,
                                onProblemTap: { store.openAutomationSettings() })
                    Spacer(minLength: 4)
                    HStack(alignment: .center) {
                        if np != nil {
                            TransportButtons(isPlaying: np?.isPlaying == true, compact: true,
                                             previous: { store.previousTrack() }, playPause: { store.playPause() },
                                             next: { store.nextTrack() })
                        }
                        Spacer(minLength: 0)
                        if let np { SourceIcon(bundleID: np.sourceAppBundleID, size: 18) { store.openSourceApp() } }
                    }
                }
                .padding(.vertical, 18)
                .frame(width: textWidth, alignment: .leading)
            )
        }
        .padding(.leading, Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Stor: større pladespiller øverst; titel, kunstner, album, tid og knapper under

    static let largeTurntableHeight: CGFloat = 232

    private func large(_ body: CGSize) -> some View {
        let w = body.width - Self.inset * 2
        let textWidth = w - 12 - 30
        return VStack(alignment: .leading, spacing: 0) {
            turntable(CGSize(width: w, height: Self.largeTurntableHeight))
            dimmed(
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        TrackHeader(np: np, problem: problem, width: textWidth, titleSize: 17, artistSize: 13, showAlbum: true,
                                onProblemTap: { store.openAutomationSettings() })
                        Spacer(minLength: 0)
                        if let np { SourceIcon(bundleID: np.sourceAppBundleID, size: 20) { store.openSourceApp() } }
                    }
                    Spacer(minLength: 2)
                    if let np {
                        HStack(alignment: .center) {
                            TimeText(np: np)
                            Spacer(minLength: 0)
                            TransportButtons(isPlaying: np.isPlaying, compact: false,
                                             previous: { store.previousTrack() }, playPause: { store.playPause() },
                                             next: { store.nextTrack() })
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 2)
            )
        }
        .padding(Self.inset)
    }
}

// MARK: - Tekst

/// Titel (fed, rulletekst), kunstner (dæmpet) og evt. album. Ved manglende tilladelse vises beskeden i stedet for kunstneren.
struct TrackHeader: View {
    let np: NowPlaying?
    let problem: SourceAccessProblem?
    let width: CGFloat
    let titleSize: CGFloat
    let artistSize: CGFloat
    let showAlbum: Bool
    var onProblemTap: () -> Void = {}
    @Environment(\.windowIsVisible) private var windowVisible

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let np {
                MarqueeText(text: TrackStrings.title(np), size: titleSize, width: width, active: np.isPlaying && windowVisible)
                if let problem {
                    ProblemText(message: problem.message, size: artistSize - 1, action: onProblemTap)
                        .layoutPriority(1)
                } else {
                    Text(TrackStrings.artist(np))
                        .font(.system(size: artistSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if showAlbum, let album = TrackStrings.album(np) {
                        Text(album)
                            .font(.system(size: artistSize - 1))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Intet spiller")
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let problem { ProblemText(message: problem.message, size: artistSize - 1, action: onProblemTap).layoutPriority(1) }
            }
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

/// `1:42 / 3:58` – opdateres én gang i sekundet og kun mens der spilles.
struct TimeText: View {
    let np: NowPlaying
    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.windowIsVisible) private var windowVisible

    var body: some View {
        if np.isPlaying && snapshot == nil && windowVisible {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in label(at: ctx.date) }
        } else {
            label(at: snapshot == nil ? .now : np.positionTimestamp)
        }
    }

    private func label(at date: Date) -> some View {
        let pos = formatTime(np.position(at: date))
        let text = np.duration > 0 ? "\(pos) / \(formatTime(np.duration))" : pos
        return Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Knapper

/// Forrige · afspil/pause · næste, i stil med Apples widgetknapper (SF Symbols, diskrete, ingen kant).
struct TransportButtons: View {
    let isPlaying: Bool
    let compact: Bool
    let previous: () -> Void
    let playPause: () -> Void
    let next: () -> Void

    var body: some View {
        let s: CGFloat = compact ? 13 : 15
        HStack(spacing: compact ? 6 : 10) {
            Button(action: previous) { symbol("backward.fill", s) }
                .accessibilityLabel("Forrige")
            Button(action: playPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: s + 3, weight: .semibold))
                    .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)
                    .background(Circle().fill(.primary.opacity(0.11)))
                    .contentShape(Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Afspil")
            Button(action: next) { symbol("forward.fill", s) }
                .accessibilityLabel("Næste")
        }
        .buttonStyle(WidgetButtonStyle())
        .foregroundStyle(.primary)
    }

    private func symbol(_ name: String, _ size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
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
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
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

/// Kildeappens ikon (Spotify/Musik); klik åbner appen. Reserve: en node.
struct SourceIcon: View {
    let bundleID: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let icon = SourceApp.icon(for: bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.6, weight: .semibold))
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
