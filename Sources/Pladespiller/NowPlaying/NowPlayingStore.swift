import AppKit
import Observation

/// Vælger hvilken kilde der vises og udgiver den til UI'et.
///
/// Fast API (andre agenter bygger på det): `current`, `start()`, `stop()`,
/// `playPause()`, `nextTrack()`, `previousTrack()`, `openSourceApp()`.
@Observable
final class NowPlayingStore {
    private(set) var current: NowPlaying?
    /// Sat når en kilde mangler tilladelse (Apple Events afvist). Udfyldes af Musikdata-agenten.
    private(set) var accessProblem: SourceAccessProblem?

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var active: NowPlayingSource?

    init(sources: [NowPlayingSource]) {
        self.sources = sources
        for source in sources {
            source.onChange = { [weak self] in self?.recompute() }
        }
    }

    /// De rigtige kilder (Spotify og Musik).
    static func defaultSources() -> [NowPlayingSource] {
        [SpotifySource(), MusicSource()]
    }

    func start() {
        sources.forEach { $0.start() }
        recompute()
    }
    func stop() { sources.forEach { $0.stop() } }

    func playPause() { active?.playPause() }
    func nextTrack() { active?.nextTrack() }
    func previousTrack() { active?.previousTrack() }
    /// Spol til en position (sekunder) i den viste sang.
    func seek(to position: TimeInterval) { active?.seek(to: position) }

    /// Åbner Systemindstillinger ▸ Anonymitet og sikkerhed ▸ Automatisering (hvor man giver adgang til Spotify/Musik).
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Åbner den app der spiller (uden at starte afspilning).
    func openSourceApp() {
        guard let id = current?.sourceAppBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Spiller flere, vises den der sidst ændrede sig. Spiller ingen, vises den sidst ændrede (på pause).
    /// Har ingen kilde en sang, er `current` nil, men knapperne går stadig til den sidst viste kilde.
    /// (`lastChange` flyttes kun ved ny sang / afspil-pause / spring, ikke når coveret ankommer,
    /// så valget ikke hopper frem og tilbage.)
    private func recompute() {
        let withTrack = sources.filter { $0.current != nil }
        let playing = withTrack.filter { $0.current?.isPlaying == true }
        let pick = (playing.isEmpty ? withTrack : playing).max { $0.lastChange < $1.lastChange }
        active = pick ?? active
        let next = pick?.current
        if next != current {
            if next?.trackKey != current?.trackKey || next?.isPlaying != current?.isPlaying
                || (next?.artwork == nil) != (current?.artwork == nil) {
                NowPlayingLog.log("[vist] " + (next.map { "\($0.isPlaying ? "▶︎" : "⏸") \($0.title) – \($0.artist) "
                    + "[\(formatTime($0.position())) / \(formatTime($0.duration))] cover:\($0.artwork == nil ? "nej" : "ja") "
                    + "kilde:\($0.sourceAppBundleID)" } ?? "intet"))
            }
            current = next
        }

        // Adgangsproblem: helst den viste kildes, ellers den aktive kildes, ellers det første.
        let problems = sources.compactMap { ($0 as? AccessReporting)?.accessProblem }
        let problem = problems.first { $0.bundleID == current?.sourceAppBundleID }
            ?? problems.first { $0.bundleID == active?.bundleID }
            ?? problems.first
        if problem != accessProblem {
            NowPlayingLog.log("[vist] adgangsproblem: \(problem?.message ?? "intet")")
            accessProblem = problem
        }
    }
}

/// En kilde der kan mangle tilladelse (Apple Events). `NowPlayingStore` samler problemerne.
protocol AccessReporting: AnyObject {
    var accessProblem: SourceAccessProblem? { get }
}
