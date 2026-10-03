import Foundation

/// `Pladespiller --nowplaying-log [--mock]`: logger hvad der spiller, uden at vise vinduet.
/// Bruges til at teste kilderne fra kommandolinjen. Ejes af Musikdata-agenten.
enum NowPlayingDebugCLI {
    static func run(mock: Bool) -> Never {
        let store = NowPlayingStore(sources: mock ? [MockNowPlayingSource()] : NowPlayingStore.defaultSources())
        store.start()
        var last: String?
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let line: String
                if let np = store.current {
                    line = "\(np.isPlaying ? "▶︎" : "⏸") \(np.title) – \(np.artist) [\(np.album)] "
                        + "\(formatTime(np.position())) / \(formatTime(np.duration)) "
                        + "cover:\(np.artwork.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "nej") "
                        + "kilde:\(np.sourceAppBundleID)"
                } else {
                    line = "Intet spiller"
                }
                if line != last { print(ISO8601DateFormatter().string(from: .now), line); fflush(stdout); last = line }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
        exit(0)
    }
}
