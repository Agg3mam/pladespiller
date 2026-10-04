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
        list.insert(NSAppleEventDescriptor(typeCode: AE.fcc("msng")), at: 4)
        list.insert(NSAppleEventDescriptor(enumCode: AE.fcc("kPSp")), at: 5)
        expect(AE.value(from: list) == .list([.text("playing"), .number(42), .number(1.5), .missing, .text("kPSp")]),
               "Descriptor → ScriptValue (inkl. missing value og rå enum-kode)")
        expect(PlayerStatus.state(from: AE.value(from: NSAppleEventDescriptor(enumCode: AE.fcc("kPSP"))).string) == .playing
               && PlayerStatus.state(from: "kPSS") == .stopped, "Rå player state-koder")

        // Object specifiers: samme struktur som AppleScript selv bygger (`a reference to` sender intet event).
        let mine = AE.prop("pRaw", of: AE.element("cArt", 1, of: AE.prop("pTrk")))
        if let ref = NSAppleScript(source: "return a reference to «class pRaw» of «class cArt» 1 of «class pTrk»")?
            .executeAndReturnError(nil) {
            expect(specifierShape(mine) == specifierShape(ref),
                   "Object specifier = AppleScripts (\(specifierShape(mine).joined(separator: " ← ")) / \(specifierShape(ref).joined(separator: " ← ")))")
        } else {
            expect(false, "Object specifier: kunne ikke lave AppleScript-reference")
        }
        expect(AE.app.descriptorType == AE.fcc("null"), "Rod-specifier er null (= appen)")

        // A1: radio/stream – cover-svaret matches på persistent ID før "|", og "intet cover" huskes
        expect(MusicSource.basePersistentID("AAAA|Kunstner X - Sang Y") == "AAAA" && MusicSource.basePersistentID("BBBB") == "BBBB",
               "Persistent ID uden stream-titel")
        expect(MusicSource.artworkAnswer(.list([.text("AAAA"), .data(Data([9]))]), for: "AAAA|Kunstner X - Sang Y") == .data(Data([9])),
               "Radio: cover-svar matcher “pid|stream”")
        expect(MusicSource.artworkAnswer(.list([.text("AAAA"), .missing]), for: "AAAA|S") == .noArtwork, "Radio uden cover → intet cover")
        expect(MusicSource.artworkAnswer(.list([.text("CCCC"), .data(Data([9]))]), for: "AAAA|S") == .otherTrack, "Andet nummer → kasseres")
        expect(MusicSource.artworkAnswer(.list([.missing, .missing]), for: "AAAA") == .noArtwork, "Ukendt pid uden data → intet cover")
        let counting = CountingArtworkSource()
        let radioStatus = PlayerStatus(state: .playing, title: "Sang Y", artist: "Kunstner X", album: "P6 Beat",
                                       position: 1, trackID: "AAAA|Kunstner X - Sang Y", artworkCount: 0)
        for i in 0..<5 {
            counting.apply(radioStatus, measuredAt: Date().addingTimeInterval(Double(i)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        expect(counting.loads == 1 && counting.current?.artwork == nil, "Intet cover huskes: kun ét cover-kald for samme sang (\(counting.loads))")

        // N6: hver app har sin egen kø – en hængende Spotify blokerer ikke Musik
        let qa = AppleEventQueue(label: "test-a"), qb = AppleEventQueue(label: "test-b")
        var bDone: Date?, aDone: Date?
        let t0q = Date()
        Task { _ = await qa.run(pid: getpid()) { _ in Thread.sleep(forTimeInterval: 0.6); return 0 }; aDone = Date() }
        Task { _ = await qb.run(pid: getpid()) { _ in 0 }; bDone = Date() }
        while aDone == nil, Date().timeIntervalSince(t0q) < 3 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        expect(bDone.map { $0.timeIntervalSince(t0q) < 0.3 } == true && aDone != nil,
               "Separate køer: Musik venter ikke på en hængende Spotify")
        expect(AETarget(pid: getpid()).timeout <= 3, "Status-timeout ≤ 3 s")

        // N7: korte tekster til widgetten
        for app in ["Spotify", "Musik"] {
            let ask = PlayerAppSource.askingMessage(app), deny = PlayerAppSource.deniedMessage(app)
            expect(ask.count <= 26 && deny.count <= 46 && !deny.contains("Anonymitet"),
                   "Kort adgangstekst: “\(ask)” / “\(deny)”")
        }

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
        src.apply(s, measuredAt: t0)
        let beforeToggle = changes
        src.applyOptimisticToggle(at: t0.addingTimeInterval(1))
        expect(src.current?.isPlaying == false && changes == beforeToggle + 1
               && abs((src.current?.position(at: t0.addingTimeInterval(9)) ?? 0) - 101) < 0.001,
               "Optimistisk pause: med det samme, position fryses")
        src.apply(s, measuredAt: t0.addingTimeInterval(1.2))   // svaret: spiller stadig → rettes
        expect(src.current?.isPlaying == true, "Optimistisk tilstand rettes af svaret")
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
        a.problem = SourceAccessProblem(bundleID: "a", message: "Giv adgang til a")
        a.clear()
        expect(store.accessProblem?.bundleID == "a", "accessProblem sættes fra kilden")
        a.problem = nil
        a.clear()
        expect(store.accessProblem == nil, "accessProblem ryddes igen")

        // Cover-cache (LRU)
        let cache = ArtworkCache(capacity: 3)
        for k in ["1", "2", "3"] { cache.insert(NSImage(size: NSSize(width: 1, height: 1)), for: k) }
        _ = cache.image(for: "1")
        cache.insert(NSImage(size: NSSize(width: 1, height: 1)), for: "4")
        expect(cache.keys == ["4", "1", "3"], "Cover-cache smider den ældste ud")

        print(failures == 0 ? "Alle \(count) test bestået." : "\(failures) af \(count) test fejlede.")
        return failures == 0
    }

    /// Kæden af (form:want:seld) fra yderst til rod, fx ["prop:prop:pRaw", "indx:cArt:1", "prop:prop:pTrk"].
    private static func specifierShape(_ d: NSAppleEventDescriptor) -> [String] {
        var out: [String] = []
        var cur: NSAppleEventDescriptor? = d
        while let c = cur, c.descriptorType == AE.fcc("obj ") {
            let form = c.forKeyword(AE.fcc("form")).map { AE.fourCCString($0.enumCodeValue) } ?? "?"
            let want = c.forKeyword(AE.fcc("want")).map { AE.fourCCString($0.typeCodeValue) } ?? "?"
            let seldDesc = c.forKeyword(AE.fcc("seld"))
            let seld = seldDesc.map { $0.descriptorType == AE.fcc("long") ? "\($0.int32Value)" : AE.fourCCString($0.typeCodeValue) } ?? "?"
            out.append("\(form):\(want):\(seld)")
            cur = c.forKeyword(AE.fcc("from"))
        }
        // AppleScript uden tell-blok har ikke appen som rod; sidste led er derfor en ren type (pTrk).
        if let root = cur, root.descriptorType == AE.fcc("type") { out.append("prop:prop:\(AE.fourCCString(root.typeCodeValue))") }
        return out
    }

    private final class CountingArtworkSource: PlayerAppSource {
        var loads = 0
        init() { super.init(bundleID: "test.counting", shortName: "test", displayName: "Test") }
        override func loadArtwork(for status: PlayerStatus) async -> ArtworkResult {
            loads += 1
            return .none
        }
    }

    private final class FakeSource: NowPlayingSource, AccessReporting {
        var problem: SourceAccessProblem?
        var accessProblem: SourceAccessProblem? { problem }
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
