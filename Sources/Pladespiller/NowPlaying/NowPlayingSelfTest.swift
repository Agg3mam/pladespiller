import AppKit

/// `--nowplaying-log --selftest`: tester parsning og logik med eksempeldata.
/// Sender ingen Apple Events og starter ingen apps.
enum NowPlayingSelfTest {
    private static var failures = 0
    private static var count = 0

    private static func expect(_ ok: Bool, _ name: String) {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "  ok    " : "  FEJL  ", name)
    }

    private static func status(_ r: StatusResult) -> PlayerStatus? {
        if case .status(let s) = r { return s }
        return nil
    }

    static func run() -> Bool {
        print("Selvtest (ingen Apple Events):")

        // Spotify: AppleScript-resultat
        let sp = status(SpotifySource.parseStatus(.list([.text("playing"), .text("Blå time"), .text("Ida & Havet"),
            .text("Lavvande"), .number(201_000), .number(40.25), .text("https://i.scdn.co/image/abc"), .text("spotify:track:1")])))
        expect(sp?.state == .playing && sp?.title == "Blå time" && sp?.duration == 201 && sp?.position == 40.25
               && sp?.artworkURL == "https://i.scdn.co/image/abc" && sp?.trackID == "spotify:track:1", "Spotify status: felter, ms → s")
        expect(status(SpotifySource.parseStatus(.list([.text("paused"), .text("A"), .text("B"), .text("C"), .text("2.38E+5"), .text("1,5"), .missing, .text("x")])))
               .map { $0.state == .paused && $0.duration == 238 && $0.position == 1.5 && $0.artworkURL == nil } == true,
               "Spotify status: tal som tekst (E-notation, komma), manglende url")
        expect(SpotifySource.parseStatus(.list([.text("notrunning")])) == .notRunning, "Spotify: kører ikke")
        expect(status(SpotifySource.parseStatus(.list([.text("stopped")])))?.state == .stopped, "Spotify: stoppet")
        expect(PlayerStatus.state(from: "«constant ****kPSp»") == .paused && PlayerStatus.state(from: "Playing") == .playing,
               "Tilstand fra rå konstant og fra notifikation")
        expect(SpotifySource.parseStatus(.text("noget andet")) == .unreadable, "Spotify: ulæseligt svar")

        // Spotify: notifikation
        let spn = SpotifySource.parseNotification(["Player State": "Playing", "Name": "Natten", "Artist": "Kobber",
            "Album": "Sort Sol", "Duration": NSNumber(value: 238_000), "Playback Position": NSNumber(value: 12.5),
            "Track ID": "spotify:track:2"])
        expect(spn?.state == .playing && spn?.duration == 238 && spn?.position == 12.5 && spn?.trackID == "spotify:track:2",
               "Spotify notifikation")
        expect(SpotifySource.parseNotification(["Player State": "Stopped"])?.state == .stopped, "Spotify notifikation: stoppet")
        expect(SpotifySource.parseNotification([:]) == nil, "Spotify notifikation: tom")

        // Musik: AppleScript-resultat
        let ms = status(MusicSource.parseStatus(.list([.text("playing"), .text("Sang"), .text("Kunstner"), .text("Album"),
            .number(201.5), .number(3.2), .text("00AB12CD34EF5678"), .number(1), .text("")])))
        expect(ms?.duration == 201.5 && ms?.position == 3.2 && ms?.trackID == "00AB12CD34EF5678" && ms?.artworkCount == 1,
               "Musik status")
        let radio = status(MusicSource.parseStatus(.list([.text("playing"), .text("P6 Beat"), .text(""), .text(""),
            .missing, .number(1234.5), .text("AAAA"), .number(0), .text("Kunstner X - Sang Y")])))
        expect(radio?.title == "Sang Y" && radio?.artist == "Kunstner X" && radio?.album == "P6 Beat"
               && radio?.duration == 0 && radio?.trackID == "AAAA|Kunstner X - Sang Y", "Musik radio/stream uden varighed")
        expect(MusicSource.parseStatus(.list([.text("notrunning")])) == .notRunning, "Musik: kører ikke")
        expect(MusicSource.parseArtwork(.list([.text("AB"), .data(Data([1, 2, 3]))]))?.1 == Data([1, 2, 3]), "Musik cover-data")
        expect(MusicSource.parseArtwork(.list([.text("AB"), .missing])).map { $0.1 == nil } == true, "Musik: intet cover")
        expect(MusicSource.parseArtwork(.list([.text("notrunning"), .missing])) == nil, "Musik cover: kører ikke")

        // Musik: notifikation
        let mn = MusicSource.parseNotification(["Player State": "Paused", "Name": "Sang", "Artist": "K", "Album": "A",
            "Total Time": NSNumber(value: 201_000), "PersistentID": NSNumber(value: Int64(-2))])
        expect(mn?.state == .paused && mn?.duration == 201 && mn?.position == nil && mn?.trackID == "FFFFFFFFFFFFFFFE",
               "Musik notifikation (negativt persistent ID → hex)")
        expect(MusicSource.persistentIDHex(NSNumber(value: Int64(0x00AB12CD34EF5678))) == "00AB12CD34EF5678", "Persistent ID hex")

        // AppleEvent-descriptor → ScriptValue
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        list.insert(NSAppleEventDescriptor(int32: 42), at: 2)
        list.insert(NSAppleEventDescriptor(double: 1.5), at: 3)
        list.insert(NSAppleEventDescriptor(typeCode: AppleScriptRunner.fcc("msng")), at: 4)
        expect(AppleScriptRunner.value(from: list) == .list([.text("playing"), .number(42), .number(1.5), .missing]),
               "Descriptor → ScriptValue")

        // Scripts starter aldrig appen
        for (name, src) in [("Spotify status", SpotifySource.statusScriptSource), ("Musik status", MusicSource.statusScriptSource),
                            ("Musik cover", MusicSource.artworkScriptSource),
                            ("Spotify playpause", SpotifySource().commandScript(.playPause)),
                            ("Musik forrige", MusicSource().commandScript(.previous))] {
            let guardLine = src.split(separator: "\n").first.map(String.init) ?? ""
            expect(guardLine.hasPrefix("if application id \"com.") && guardLine.hasSuffix("is running then"),
                   "\(name)-script er beskyttet af “is running”")
        }

        // Kilde-logik: position, ændringer, lastChange
        let src = SpotifySource()
        var changes = 0
        src.onChange = { changes += 1 }
        let t0 = Date()
        var s = PlayerStatus(state: .playing, title: "A", artist: "B", album: "C", duration: 200, position: 10, trackID: "id1")
        src.apply(s, measuredAt: t0)
        expect(changes == 1 && abs((src.current?.position(at: t0.addingTimeInterval(2)) ?? 0) - 12) < 0.001,
               "position(at:) = position + tid siden måling")
        let lc = src.lastChange
        s.position = 10.3
        src.apply(s, measuredAt: t0)          // lille afvigelse → ingen ændring
        expect(changes == 1, "Lille afvigelse (<0,75 s) giver ingen opdatering")
        s.position = 11.5
        src.apply(s, measuredAt: t0)          // 1,5 s → justering uden lastChange
        expect(changes == 2 && src.lastChange == lc, "Afvigelse 1,5 s: justeres, lastChange uændret")
        s.position = 100
        src.apply(s, measuredAt: t0)
        expect(changes == 3 && src.lastChange > lc, "Spring i sangen: lastChange flyttes")
        var p = s
        p.state = .paused
        p.position = nil
        src.apply(p, measuredAt: t0.addingTimeInterval(5))   // fx Musik-notifikation uden position
        expect(src.current?.isPlaying == false && abs((src.current?.position ?? 0) - 105) < 0.001,
               "Pause uden position: position forudsiges")
        src.apply(PlayerStatus(state: .stopped), measuredAt: .now)
        expect(src.current == nil, "Stoppet → intet spiller")

        // Store: vælger den der sidst ændrede sig blandt dem der spiller
        let a = FakeSource(id: "a"), b = FakeSource(id: "b")
        let store = NowPlayingStore(sources: [a, b])
        a.set(playing: true, at: Date(timeIntervalSinceNow: -10))
        b.set(playing: true, at: .now)
        expect(store.current?.sourceAppBundleID == "b", "Begge spiller → den senest ændrede")
        b.set(playing: false, at: .now)
        expect(store.current?.sourceAppBundleID == "a", "Kun én spiller → den")
        a.set(playing: false, at: Date(timeIntervalSinceNow: -5))
        expect(store.current?.sourceAppBundleID == "b", "Ingen spiller → den senest ændrede (på pause)")
        a.clear(); b.clear()
        expect(store.current == nil, "Ingen sange → nil")

        // Cover-cache (LRU)
        let cache = ArtworkCache(capacity: 3)
        for k in ["1", "2", "3"] { cache.insert(NSImage(size: NSSize(width: 1, height: 1)), for: k) }
        _ = cache.image(for: "1")
        cache.insert(NSImage(size: NSSize(width: 1, height: 1)), for: "4")
        expect(cache.keys == ["4", "1", "3"], "Cover-cache smider den ældste ud")

        print(failures == 0 ? "Alle \(count) test bestået." : "\(failures) af \(count) test fejlede.")
        return failures == 0
    }

    private final class FakeSource: NowPlayingSource {
        let bundleID: String
        private(set) var current: NowPlaying?
        private(set) var lastChange = Date.distantPast
        var onChange: (() -> Void)?
        init(id: String) { bundleID = id }
        func set(playing: Bool, at date: Date) {
            current = NowPlaying(title: bundleID, artist: "", album: "", artwork: nil, duration: 100, position: 0,
                                 positionTimestamp: date, isPlaying: playing, sourceAppBundleID: bundleID)
            lastChange = date
            onChange?()
        }
        func clear() { current = nil; lastChange = .now; onChange?() }
        func start() {}
        func stop() {}
        func playPause() {}
        func nextTrack() {}
        func previousTrack() {}
    }
}
