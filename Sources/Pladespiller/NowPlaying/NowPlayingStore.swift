import AppKit
import Observation

/// Vælger hvilken kilde der vises og udgiver den til UI'et.
///
/// Fast API (andre agenter bygger på det): `current`, `start()`, `stop()`,
/// `playPause()`, `nextTrack()`, `previousTrack()`, `openSourceApp()`.
@Observable
final class NowPlayingStore {
    private(set) var current: NowPlaying?

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var active: NowPlayingSource?

    init(sources: [NowPlayingSource]) {
        self.sources = sources
        for source in sources {
            source.onChange = { [weak self] in self?.recompute() }
        }
    }

    /// De rigtige kilder (Spotify og Musik). Udfyldes af Musikdata-agenten.
    static func defaultSources() -> [NowPlayingSource] {
        []
    }

    func start() { sources.forEach { $0.start() } }
    func stop() { sources.forEach { $0.stop() } }

    func playPause() { active?.playPause() }
    func nextTrack() { active?.nextTrack() }
    func previousTrack() { active?.previousTrack() }

    /// Åbner den app der spiller (uden at starte afspilning).
    func openSourceApp() {
        guard let id = current?.sourceAppBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Spiller flere, vises den der sidst ændrede sig. Spiller ingen, vises den sidst ændrede (på pause).
    private func recompute() {
        let withTrack = sources.filter { $0.current != nil }
        let playing = withTrack.filter { $0.current?.isPlaying == true }
        let pick = (playing.isEmpty ? withTrack : playing).max { $0.lastChange < $1.lastChange }
        active = pick ?? active
        let next = pick?.current
        if next != current { current = next }
    }
}
