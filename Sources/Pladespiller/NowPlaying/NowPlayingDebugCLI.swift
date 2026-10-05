import AppKit

/// `Pladespiller --nowplaying-log [flag]`: logger hvad der spiller, uden at vise vinduet.
/// Bruges til at teste kilderne fra kommandolinjen. Ejes af Musikdata-agenten.
///
/// Flag:
///   --mock                 testkilden i stedet for Spotify/Musik
///   --selftest             kør parser-/logiktest på eksempeldata (sender ingen Apple Events) og afslut
///   --cmd playpause|next|previous|seek:<sekunder>   send en kommando 2 s efter start
///   --app spotify|music    hvilken app --cmd sendes til (standard: den der vises)
///   --print-scripts        udskriv AppleScript-reservens scripts, og afslut
///   --applescript          brug AppleScript-reserven i stedet for Apple Events til pid (virker også i appen)
///   --log                  skriv også til ~/Library/Logs/Pladespiller/nowplaying.log (virker også i appen)
///   --lyrics "Titel" "Kunstner" [sek] ["Album"]   hent fra LRCLIB (uden diskcache), print linjerne, og afslut
///   --quiet                kun ændringer i det viste, ikke kildernes hændelser
enum NowPlayingDebugCLI {
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func out(_ s: String) {
        print(clock.string(from: .now), s)
        fflush(stdout)
    }

    static func run(mock: Bool) -> Never {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        if args.contains("--print-scripts") {
            let scripts: [(String, String)] = [
                ("spotify-status", SpotifySource.statusScriptSource),
                ("spotify-playpause", SpotifySource().commandScript(.playPause)),
                ("musik-status", MusicSource.statusScriptSource),
                ("musik-cover", MusicSource.artworkScriptSource),
                ("musik-forrige", MusicSource().commandScript(.previous)),
            ]
            for (name, src) in scripts { print("-- \(name)\n\(src)\n") }
            exit(0)
        }
        if let i = args.firstIndex(of: "--lyrics") {
            let rest = Array(args[(i + 1)...]).prefix { !$0.hasPrefix("--") }
            guard rest.count >= 2 else {
                print("Brug: --lyrics \"Titel\" \"Kunstner\" [sekunder] [\"Album\"]")
                exit(2)
            }
            NowPlayingLog.handler = { out("  · " + $0) }
            let q = LyricsService.Query(title: rest[rest.startIndex], artist: rest[rest.startIndex + 1],
                                        album: rest.count > 3 ? rest[rest.startIndex + 3] : "",
                                        duration: rest.count > 2 ? Double(rest[rest.startIndex + 2]) ?? 0 : 0)
            // Uden diskcache, så LRCLIB faktisk spørges.
            let service = LyricsService(cache: LyricsCache(directory: nil))
            Task {
                let state = await service.lyrics(for: q, trackKey: "cli")
                switch state {
                case .found(let l):
                    if l.instrumental { print("(instrumental)") }
                    for line in l.lines {
                        let words = line.words.isEmpty ? "" : "  {\(line.words.count) ord}"
                        print(String(format: "[%@.%02d] ", formatTime(line.start), Int((line.start * 100).truncatingRemainder(dividingBy: 100)))
                              + (line.isInstrumental ? "♪" : line.text) + words)
                    }
                    exit(0)
                default:
                    print("Ikke fundet")
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
        if args.contains("--selftest") {
            exit(NowPlayingSelfTest.run() ? 0 : 1)
        }

        if !args.contains("--quiet") { NowPlayingLog.handler = { out("  · " + $0) } }

        let sources: [NowPlayingSource] = mock ? [MockNowPlayingSource()] : NowPlayingStore.defaultSources()
        let store = NowPlayingStore(sources: sources)
        out("Starter (\(mock ? "testkilde" : "Spotify + Musik")). Ctrl-C for at stoppe.")
        store.start()

        if let cmd = value(after: "--cmd") {
            let app = value(after: "--app")
            Task {
                try? await Task.sleep(for: .seconds(2))
                do {
                    let target: NowPlayingSource?
                    switch app {
                    case "spotify": target = sources.first { $0.bundleID == NowPlaying.BundleID.spotify }
                    case "music", "musik": target = sources.first { $0.bundleID == NowPlaying.BundleID.music }
                    default: target = nil
                    }
                    out("Sender \(cmd) til \(target?.bundleID ?? "den viste kilde")")
                    switch cmd {
                    case "playpause": target.map { $0.playPause() } ?? store.playPause()
                    case "next": target.map { $0.nextTrack() } ?? store.nextTrack()
                    case "previous", "prev": target.map { $0.previousTrack() } ?? store.previousTrack()
                    case let c where c.hasPrefix("seek:"):
                        let secs = Double(c.dropFirst(5).replacingOccurrences(of: ",", with: ".")) ?? 0
                        target.map { $0.seek(to: secs) } ?? store.seek(to: secs)
                    default: out("Ukendt kommando: \(cmd) (brug playpause, next, previous, seek:<sekunder>)")
                    }
                }
            }
        }

        var last: String?
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                let line: String
                if let np = store.current {
                    line = "\(np.isPlaying ? "▶︎" : "⏸") \(np.title) – \(np.artist) [\(np.album)] "
                        + "\(formatTime(np.position())) / \(np.duration > 0 ? formatTime(np.duration) : "?") "
                        + "cover:\(np.artwork.map(PlayerAppSource.pixelSize) ?? "nej") "
                        + "kilde:\(np.sourceAppBundleID)"
                } else {
                    line = "Intet spiller"
                }
                if line != last { out(line); last = line }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
        exit(0)
    }
}
