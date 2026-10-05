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
    /// Sangtekst til den viste sang (LRCLIB). `var`, så snapshots kan sætte den direkte.
    var lyrics: LyricsState = .off
    /// Sangtekst slået til (sættes af App.swift fra `settings.showLyrics`). Fra → `lyrics = .off`, ingen hentning.
    var lyricsEnabled = false {
        didSet { if lyricsEnabled != oldValue { refreshLyrics() } }
    }

    @ObservationIgnored private lazy var lyricsService = LyricsService()
    @ObservationIgnored private var lyricsTrackKey: String?
    @ObservationIgnored private var lyricsRequested = false

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

    /// Ny sang → `.loading` og hent (fra cache, ellers LRCLIB – men kun mens der spilles).
    /// Svar der hører til en sang, som ikke længere vises, kasseres.
    private func refreshLyrics() {
        guard lyricsEnabled, let np = current else {
            lyricsTrackKey = nil
            lyricsRequested = false
            setLyrics(.off)
            return
        }
        let key = np.trackKey
        if key != lyricsTrackKey {
            lyricsTrackKey = key
            lyricsRequested = false
            if np.sourceAppBundleID == NowPlaying.BundleID.mock {
                // Testkilden har opdigtede sange: spørg aldrig LRCLIB.
                lyricsRequested = true
                setLyrics(.notFound)
                return
            }
            if let hit = lyricsService.cached(Self.lyricsQuery(np), trackKey: key) {
                lyricsRequested = true
                setLyrics(hit)
                return
            }
            setLyrics(.loading)
        }
        guard !lyricsRequested, np.isPlaying else { return }   // ingen hentning mens intet spiller
        lyricsRequested = true
        let query = Self.lyricsQuery(np)
        Task {
            let result = await self.lyricsService.lyrics(for: query, trackKey: key)
            guard self.lyricsEnabled, self.lyricsTrackKey == key else {
                NowPlayingLog.log("[lyrics] svar til en sang der ikke længere vises – kasseret")
                return
            }
            self.setLyrics(result)
        }
    }

    private func setLyrics(_ state: LyricsState) {
        if state != lyrics { lyrics = state }
    }

    static func lyricsQuery(_ np: NowPlaying) -> LyricsService.Query {
        .init(title: np.title, artist: np.artist, album: np.album, duration: np.duration)
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
            refreshLyrics()
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
