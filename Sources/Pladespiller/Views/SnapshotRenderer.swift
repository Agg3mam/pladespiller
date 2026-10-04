import AppKit
import SwiftUI

/// `Pladespiller --render-snapshots <dir>`: tegner visninger med testdata til PNG uden at vise noget vindue.
/// Ejes af Grafik-agenten.
///
/// Hver scene er en række hændelser (tid → NowPlaying) og et tidspunkt der tegnes. Samme `TurntableAnimator`
/// som live bruges til at regne posen ud, så snapshots viser præcis hvad Core Animation vil vise til det tidspunkt.
enum SnapshotRenderer {
    struct Scene {
        var name: String
        var events: [(Double, NowPlaying?)]
        var time: Double
        var size: WidgetSize = .medium
        var theme: TurntableTheme = .wood
        var dark = true
        var titleStyle: TitleStyle = .marquee
        var marqueePhase: Double? = nil
        var dim: Double = 0
        var hover = false
        var problem: SourceAccessProblem? = nil
        /// Baggrund: neutral flade (som widgettens uigennemsigtige flade) eller "skrivebord" med dæmpet, gennemsigtig flade.
        var desktop = false
        var speed: SpinSpeed = .calm
        /// Kun layout-tjek: tegn kun dette element på gennemsigtig baggrund.
        var probe: String? = nil
        var caption: String = ""
    }

    static let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// QA K7: snapshots bruger et midlertidigt UserDefaults-domæne, som slettes bagefter.
    static let defaultsSuite = "pladespiller.snapshots.\(ProcessInfo.processInfo.processIdentifier)"

    static func np(_ i: Int, playing: Bool = true, progress: Double, at t: Double, app: String? = nil) -> NowPlaying {
        var n = MockNowPlayingSource.sample(i, isPlaying: playing, progress: progress, at: base.addingTimeInterval(t))
        if let app { n.sourceAppBundleID = app }
        return n
    }

    static func run(outputDirectory dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuite) }
        let started = Date()
        WoodTexture.loadSynchronously()
        let env = ProcessInfo.processInfo.environment
        if env["PLADESPILLER_SNAPSHOT_LAYOUT"] == "1" {        // hurtig gentagelse af layoutarbejdet
            layoutCheck(dir); largeFinal(dir); beforeAfter(dir); return
        }
        let live = LiveSequenceTest.run(dir: dir)
        try? live.joined(separator: "\n").write(to: dir.appendingPathComponent("live-tjek.txt"), atomically: true, encoding: .utf8)
        print(live.joined(separator: "\n"))
        if ProcessInfo.processInfo.environment["PLADESPILLER_SNAPSHOT_ONLY_LIVE"] == "1" { return }
        woodCloseUp(dir)
        if ProcessInfo.processInfo.environment["PLADESPILLER_SNAPSHOT_ONLY_WOOD"] == "1" { return }
        if ProcessInfo.processInfo.environment["PLADESPILLER_SNAPSHOT_LAYOUT"] == "1" {
            layoutCheck(dir); largeFinal(dir); beforeAfter(dir); return
        }
        let music = NowPlaying.BundleID.music

        // Basis: alle tre størrelser i standardtilstand.
        for size in WidgetSize.allCases {
            write(scene(Scene(name: "widget-\(size.rawValue)", events: [(0, np(0, progress: 0.3, at: 0, app: music))], time: 4, size: size)),
                  to: dir.appendingPathComponent("widget-\(size.rawValue).png"))
        }

        layoutCheck(dir)
        largeFinal(dir)
        beforeAfter(dir)

        // 1. Afspil: flere vinkler og fremdrifter
        let playing = [0.0, 0.25, 0.5, 0.75].map { dt in
            Scene(name: "afspil-vinkel-\(Int(dt * 100))", events: [(0, np(0, progress: 0.3, at: 0))], time: 4 + dt,
                  caption: String(format: "afspil t=%.2f s", 4 + dt))
        } + [0.0, 0.5, 1.0].map { p in
            Scene(name: "afspil-fremdrift-\(Int(p * 100))", events: [(0, np(1, progress: p, at: 0))], time: 2,
                  caption: "fremdrift \(Int(p * 100)) %")
        }
        sheet("01-afspil", playing, dir: dir, columns: 2)

        // 2. Pause og afspil igen
        let pauseEvents: [(Double, NowPlaying?)] = [(0, np(0, progress: 0.4, at: 0)), (5, np(0, playing: false, progress: 0.4 + 5 / 238, at: 5)),
                                                    (8, np(0, playing: true, progress: 0.4 + 5 / 238, at: 8))]
        let pause = [4.9, 5.15, 5.4, 5.65, 6.3, 7.5, 8.2, 8.45, 8.7, 9.5].map { t in
            Scene(name: "pause-\(t)", events: pauseEvents, time: t,
                  caption: String(format: "%@ t=%.2f", t < 5 ? "spiller" : t < 8 ? "pause" : "afspil igen", t))
        }
        sheet("02-pause", pause, dir: dir, columns: 2)

        // 3. Ny sang midt i overgangen
        let changeEvents: [(Double, NowPlaying?)] = [(0, np(0, progress: 0.97, at: 0)), (5, np(1, progress: 0, at: 5))]
        let change = [4.9, 5.12, 5.3, 5.45, 5.6, 5.75, 5.9, 6.5].map { t in
            Scene(name: "ny-sang-\(t)", events: changeEvents, time: t, caption: String(format: "ny sang %+.2f s", t - 5))
        }
        sheet("03-ny-sang", change, dir: dir, columns: 2)

        // 4. Tilstande: intet, uden cover, manglende adgang, tom titel/kunstner
        var blank = np(1, progress: 0.3, at: 0, app: music)
        blank.title = ""; blank.artist = ""
        let problem = SourceAccessProblem(bundleID: NowPlaying.BundleID.spotify, message: "Giv adgang til Spotify i Systemindstillinger")
        let misc: [Scene] = [
            Scene(name: "intet", events: [(0, np(0, progress: 0.4, at: 0)), (1, nil)], time: 4, caption: "intet spiller"),
            Scene(name: "intet-lille", events: [(0, nil)], time: 4, size: .small, caption: "intet spiller (lille)"),
            Scene(name: "uden-cover", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, caption: "uden cover"),
            Scene(name: "uden-cover-lys", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, dark: false, caption: "uden cover, lys"),
            Scene(name: "adgang", events: [(0, np(0, playing: false, progress: 0.4, at: 0))], time: 3, problem: problem, caption: "manglende adgang"),
            Scene(name: "adgang-intet", events: [(0, nil)], time: 3, problem: problem, caption: "manglende adgang, intet"),
            Scene(name: "adgang-lille", events: [(0, nil)], time: 3, size: .small, problem: problem, caption: "manglende adgang (lille)"),
            Scene(name: "tom-titel", events: [(0, blank)], time: 3, caption: "tom titel og kunstner (Musik)"),
        ]
        sheet("04-tilstande", misc, dir: dir, columns: 2)

        // 5. Rulletekst (standard) og "…" til sammenligning
        let long = np(2, progress: 0.2, at: 0, app: music)
        let titles: [Scene] = [
            Scene(name: "rul-0", events: [(0, long)], time: 3, marqueePhase: 0, caption: "rulletekst: pause ved start"),
            Scene(name: "rul-30", events: [(0, long)], time: 3, marqueePhase: 0.3, caption: "rulletekst undervejs"),
            Scene(name: "rul-80", events: [(0, long)], time: 3, marqueePhase: 0.8, caption: "rulletekst næsten forfra"),
            Scene(name: "rul-lys", events: [(0, long)], time: 3, dark: false, marqueePhase: 0.3, caption: "rulletekst, lys"),
            Scene(name: "rul-stor", events: [(0, long)], time: 3, size: .large, marqueePhase: 0.3, caption: "rulletekst, stor"),
            Scene(name: "ellipse", events: [(0, long)], time: 3, titleStyle: .ellipsis, caption: "\"…\" (ikke standard)"),
        ]
        sheet("05-rulletekst", titles, dir: dir, columns: 2)

        // 6. Størrelser × temaer × lys/mørk
        for dark in [true, false] {
            var scenes: [Scene] = []
            for theme in TurntableTheme.allCases {
                for size in WidgetSize.allCases {
                    scenes.append(Scene(name: "\(size.rawValue)-\(theme.rawValue)", events: [(0, np(theme == .auto ? 1 : 0, progress: 0.3, at: 0, app: music))],
                                        time: 4, size: size, theme: theme, dark: dark, caption: "\(theme.title) · \(size.title)"))
                }
            }
            sheet(dark ? "06-temaer-moerk" : "07-temaer-lys", scenes, dir: dir, columns: 3)
        }

        // 7. Knapper og hover
        let buttons: [Scene] = [
            Scene(name: "lille-uden-hover", events: [(0, np(0, progress: 0.3, at: 0))], time: 4, size: .small, caption: "lille, mus ikke over"),
            Scene(name: "lille-hover", events: [(0, np(0, progress: 0.3, at: 0))], time: 4, size: .small, hover: true, caption: "lille, mus over (spiller)"),
            Scene(name: "lille-hover-pause", events: [(0, np(0, playing: false, progress: 0.3, at: 0))], time: 4, size: .small, hover: true, caption: "lille, mus over (pause)"),
            Scene(name: "mellem-spiller", events: [(0, np(0, progress: 0.3, at: 0, app: music))], time: 4, caption: "mellem, spiller"),
            Scene(name: "mellem-pause", events: [(0, np(1, playing: false, progress: 0.3, at: 0, app: music))], time: 4, dark: false, caption: "mellem, pause, lys"),
            Scene(name: "stor-spiller", events: [(0, np(1, progress: 0.42, at: 0, app: music))], time: 4, size: .large, caption: "stor, spiller"),
            Scene(name: "stor-pause-lys", events: [(0, np(0, playing: false, progress: 0.42, at: 0, app: music))], time: 4, size: .large, dark: false, caption: "stor, pause, lys"),
        ]
        let speedScenes: [Scene] = [
            Scene(name: "fart-33", events: [(0, np(0, progress: 0.3, at: 0, app: music))], time: 4, size: .small, speed: .rpm33,
                  caption: "33 aktiv (33⅓ o/min)"),
            Scene(name: "fart-45", events: [(0, np(0, progress: 0.3, at: 0, app: music))], time: 4, size: .small, speed: .rpm45,
                  caption: "45 aktiv (45 o/min)"),
            Scene(name: "fart-45-stor", events: [(0, np(1, progress: 0.3, at: 0, app: music))], time: 4, size: .large, speed: .rpm45,
                  caption: "45 aktiv · stor"),
        ]
        sheet("08-knapper-hover", buttons + speedScenes, dir: dir, columns: 3)

        // 8. Dæmpet mod fuld farve (dæmpet flade er gennemsigtig over sløret skrivebord)
        var dimmed: [Scene] = []
        for (size, dark) in [(WidgetSize.medium, true), (.medium, false), (.small, true), (.large, true)] {
            for d in [0.0, 0.5, 1.0] {
                dimmed.append(Scene(name: "daemp-\(size.rawValue)-\(d)", events: [(0, np(0, progress: 0.3, at: 0, app: music))], time: 4,
                                    size: size, dark: dark, dim: d, desktop: true,
                                    caption: "\(size.title)\(dark ? "" : ", lys"): dæmpning \(Int(d * 100)) %"))
            }
        }
        sheet("09-daempning", dimmed, dir: dir, columns: 3)

        // 9. Store enkeltbilleder
        write(scene(Scene(name: "stor-trae", events: [(0, np(0, progress: 0.35, at: 0, app: music))], time: 4, size: .large)),
              to: dir.appendingPathComponent("detalje-stor-trae.png"), scale: 3)
        write(scene(Scene(name: "mellem-trae", events: [(0, np(0, progress: 0.35, at: 0, app: music))], time: 4)),
              to: dir.appendingPathComponent("detalje-mellem-trae.png"), scale: 3)

        spinReport(to: dir.appendingPathComponent("spin-vinkler.txt"))
        armReport(to: dir.appendingPathComponent("arm-vinkler.txt"))
        caCheck(to: dir.appendingPathComponent("ca-tjek.txt"))
        print(String(format: "Snapshots færdige på %.1f s", Date().timeIntervalSince(started)))
    }

    // MARK: Scene → view

    static func pose(for s: Scene) -> TurntablePose {
        var a = TurntableAnimator(geometry: TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: 20))
        a.setSpeed(s.speed, at: 0)
        for (t, n) in s.events where t <= s.time {
            a.update(n.map { TurntableInput($0, at: base.addingTimeInterval(t)) }, at: t)
        }
        return a.pose(at: s.time)
    }

    static func current(for s: Scene) -> NowPlaying? {
        guard let last = s.events.last(where: { $0.0 <= s.time }) else { return nil }
        return last.1
    }

    static func scene(_ s: Scene) -> some View {
        let settings = Settings(defaults: UserDefaults(suiteName: defaultsSuite)!)
        settings.size = s.size
        settings.theme = s.theme
        settings.spinSpeed = s.speed
        let store = NowPlayingStore(sources: [FixedSource(current(for: s))])
        store.start()
        let presentation = WidgetPresentation()
        presentation.dimAmount = s.dim
        presentation.isHovering = s.hover
        let body = WidgetMetrics.bodySize(for: s.size)
        let scheme: ColorScheme = s.dark ? .dark : .light
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
        return WidgetView()
            .frame(width: body.width, height: body.height)
            .background {
                if s.probe != nil {
                    Color.clear
                } else if s.desktop {
                    // Som Vinduets dæmpede flade: baggrundens opacitet falder mod dimBackgroundOpacity.
                    WidgetBackground(scheme: scheme).opacity(1 - (1 - WidgetMetrics.dimBackgroundOpacity) * s.dim)
                } else {
                    WidgetBackground(scheme: scheme)
                }
            }
            .clipShape(shape)
            .padding(s.desktop ? 8 : 0)
            .background { if s.desktop { FakeDesktop(dark: s.dark).clipped() } }
            .environment(settings)
            .environment(store)
            .environment(\.widgetPresentation, presentation)
            .environment(\.turntableSnapshot, TurntableSnapshotPose(pose: pose(for: s), dim: s.dim))
            .environment(\.titleStyle, s.titleStyle)
            .environment(\.marqueePhase, s.marqueePhase)
            .environment(\.snapshotAccessProblem, s.problem)
            .environment(\.layoutProbe, s.probe)
            .environment(\.colorScheme, scheme)
            .environment(\.displayScale, 2)
    }

    /// Kontaktark: flere scener i et gitter med billedtekst.
    static func sheet(_ name: String, _ scenes: [Scene], dir: URL, columns: Int, scale: CGFloat = 2) {
        let rows = stride(from: 0, to: scenes.count, by: columns).map { Array(scenes[$0..<min($0 + columns, scenes.count)]) }
        let view = VStack(alignment: .leading, spacing: 14) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let s = rows[r][c]
                        VStack(alignment: .leading, spacing: 4) {
                            scene(s)
                            Text(s.caption.isEmpty ? s.name : s.caption)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(white: 0.85))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.30))
        write(view, to: dir.appendingPathComponent("\(name).png"), scale: scale)
    }

    static func write(_ view: some View, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view.environment(\.displayScale, scale))
        renderer.scale = scale
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("Kunne ikke tegne \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("Skrev \(url.path)")
    }

    // MARK: Tal

    /// Simulerer: start → pause midt i opspeedningen → afspil midt i nedbremsningen → pause → intet.
    /// Skriver vinkel og hastighed hver 20. ms og tjekker at både vinkel og hastighed er kontinuerte.
    static func spinReport(to url: URL) {
        let g = TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: 20)
        var a = TurntableAnimator(geometry: g)
        let events: [(Double, NowPlaying?)] = [
            (0, np(0, playing: false, progress: 0.2, at: 0)),
            (1.0, np(0, playing: true, progress: 0.2, at: 1.0)),      // start
            (1.4, np(0, playing: false, progress: 0.2, at: 1.4)),     // pause midt i opspeedning
            (1.9, np(0, playing: true, progress: 0.2, at: 1.9)),      // afspil midt i nedbremsning
            (4.0, np(0, playing: false, progress: 0.21, at: 4.0)),    // pause fra fuld fart
            (6.0, nil),
        ]
        // Hastighedsskift mens der spilles (som en rigtig pladespiller der skifter 33 → 45): 45 ved 2,6 s,
        // 'Langsom' ved 2,9 s (midt i den rampe), 'Rolig' igen ved 3,5 s.
        a.setSpeed(.calm, at: 0)
        let speedEvents: [(Double, SpinSpeed)] = [(2.6, .rpm45), (2.9, .slow), (3.5, .calm)]
        var si = 0
        var lines = ["# t (s)\tvinkel (grader)\thastighed (o/min)\tΔvinkel/Δt (o/min)"]
        var prevAngle: Double?, prevV: Double?
        var maxVJump = 0.0, maxMismatch = 0.0
        var ei = 0
        let dt = 0.02
        var t = 0.0
        while t <= 7.5 + 1e-9 {
            while si < speedEvents.count, speedEvents[si].0 <= t + 1e-9 {
                a.setSpeed(speedEvents[si].1, at: speedEvents[si].0)
                lines.append("# hastighed t=\(speedEvents[si].0): \(speedEvents[si].1.title)")
                si += 1
            }
            while ei < events.count, events[ei].0 <= t + 1e-9 {
                a.update(events[ei].1.map { TurntableInput($0, at: base.addingTimeInterval(events[ei].0)) }, at: events[ei].0)
                lines.append("# hændelse t=\(events[ei].0): \(events[ei].1.map { $0.isPlaying ? "afspil" : "pause" } ?? "intet")")
                ei += 1
            }
            let ang = a.spin.angle(at: t), v = a.spin.velocity(at: t)
            let rpm = v / (2 * .pi) * 60
            var diffRpm = Double.nan
            if let pa = prevAngle {
                diffRpm = (ang - pa) / dt / (2 * .pi) * 60
                // vinklen kan være pakket ved 2π når en ny rampe starter; tag højde for det
                if abs(diffRpm) > 200 { diffRpm = (ang - pa + 2 * .pi * ((pa - ang) / (2 * .pi)).rounded()) / dt / (2 * .pi) * 60 }
            }
            if let pv = prevV { maxVJump = max(maxVJump, abs(rpm - pv)) }
            if !diffRpm.isNaN, let pv = prevV { maxMismatch = max(maxMismatch, abs(diffRpm - (pv + rpm) / 2)) }
            lines.append(String(format: "%.2f\t%9.2f\t%6.2f\t%6.2f", t, ang * 180 / .pi, rpm, diffRpm))
            prevAngle = ang; prevV = rpm
            t += dt
        }
        let summary = String(format: "Største hastighedsspring mellem to samples (20 ms): %.2f o/min (fuld fart = %.2f). "
                             + "Største afvigelse mellem Δvinkel/Δt og hastighed: %.3f o/min.", maxVJump, 60 / WidgetMetrics.secondsPerRevolution, maxMismatch)
        lines.insert("# " + summary, at: 0)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print(summary)
        print("Skrev \(url.path)")
    }

    /// Armens vinkel og løft gennem pause, afspil og ny sang.
    static func armReport(to url: URL) {
        let g = TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: 20)
        var a = TurntableAnimator(geometry: g)
        let events: [(Double, NowPlaying?)] = [
            (0, np(0, progress: 0.5, at: 0)), (2, np(0, playing: false, progress: 0.5 + 2 / 238, at: 2)),
            (4, np(0, progress: 0.5 + 2 / 238, at: 4)), (6, np(1, progress: 0, at: 6)), (8, nil),
        ]
        var lines = [String(format: "# hvile %.2f°, yderste rille %.2f°, inderste rille %.2f°",
                            g.restAngle * 180 / .pi, g.armAngle(forProgress: 0) * 180 / .pi, g.armAngle(forProgress: 1) * 180 / .pi),
                     "# t (s)\tarm (grader)\tløft"]
        var ei = 0
        var t = 0.0
        while t <= 9.5 + 1e-9 {
            while ei < events.count, events[ei].0 <= t + 1e-9 {
                a.update(events[ei].1.map { TurntableInput($0, at: base.addingTimeInterval(events[ei].0)) }, at: events[ei].0)
                ei += 1
            }
            let p = a.pose(at: t)
            lines.append(String(format: "%.2f\t%7.3f\t%.3f", t, p.armAngle * 180 / .pi, p.armLift))
            t += 0.05
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("Skrev \(url.path)")
    }
}

extension SnapshotRenderer {
    /// Nærbillede af træet: den store krop (foto + lys, lak, kant) i 4× skala, et udsnit, og det tegnede reservetræ.
    static func woodCloseUp(_ dir: URL) {
        let g = TurntableGeometry(size: CGSize(width: 344, height: 344), cornerRadius: WidgetMetrics.cornerRadius,
                                  deck: WidgetView.largeDeck(WidgetMetrics.bodySize(for: .large)))
        let style = TurntableStyle(plinth: .wood(.walnut), darkHardware: false)
        print(WoodTexture.findFile().map { "Træfoto: \($0.path)" } ?? "Intet træfoto fundet – bruger tegnet træ")
        func save(_ img: CGImage?, _ name: String) {
            guard let img, let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
            try? png.write(to: dir.appendingPathComponent(name))
        }
        let plinth = PlinthRenderer.image(g, style: style, scale: 4)
        save(plinth, "trae-naerbillede.png")
        save(plinth?.cropping(to: CGRect(x: 0, y: 0, width: 700, height: 520)), "trae-udsnit.png")
        let veneer = WoodVeneer(species: .walnut)
        save(Drawing.pixels(size: CGSize(width: 160, height: 120), scale: 4) { x, y in
            let c = veneer.color(x, y); return SIMD4(c.x, c.y, c.z, 1)
        }, "trae-reserve-tegnet.png")
    }

    /// Tjekker live-vejen uden vindue: lægger CA-animationerne ind og sammenligner keyframes med den analytiske pose.
    static func caCheck(to url: URL) {
        let g = TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: 20)
        let layer = TurntableLayer()
        // Ny størrelse (ikke i cachen) for at måle hvad det koster at tegne alle billeder første gang.
        let fresh = TurntableGeometry(size: CGSize(width: 149, height: 149), cornerRadius: 20)
        let t0 = Date()
        WoodTexture.loadSynchronously()
        layer.configure(fresh, style: TurntableStyle.make(theme: .wood, artwork: nil), scale: 2)
        let buildMs = Date().timeIntervalSince(t0) * 1000
        let t1 = Date()
        layer.configure(fresh, style: TurntableStyle.make(theme: .wood, artwork: nil), scale: 2)
        let cachedMs = Date().timeIntervalSince(t1) * 1000
        layer.configure(g, style: TurntableStyle.make(theme: .wood, artwork: nil), scale: 2)
        var lines = [String(format: "Alle billeder tegnet første gang @2x: %.0f ms; igen (cache): %.2f ms", buildMs, cachedMs)]
        var a = TurntableAnimator(geometry: g)
        let now = 1000.0
        a.update(nil, at: now - 5)
        let events: [(Double, NowPlaying?)] = [(now, np(0, progress: 0.3, at: 0)), (now + 3, np(0, playing: false, progress: 0.3 + 3 / 238, at: 3))]
        for (t, n) in events {
            a.update(n.map { TurntableInput($0, at: base.addingTimeInterval(t - now)) }, at: t)
            layer.sync(a, at: t)
            lines.append(String(format: "Efter hændelse t=%+.1f (%@):", t - now, n?.isPlaying == true ? "afspil" : "pause"))
            for (name, l) in layer.debugLayers {
                for key in l.animationKeys() ?? [] {
                    guard let anim = l.animation(forKey: key) else { continue }
                    var desc = String(format: "  %@.%@: varighed %.2f s", name, key, anim.duration)
                    if anim.repeatCount.isInfinite { desc += ", gentages uendeligt" }
                    if let kf = anim as? CAKeyframeAnimation { desc += ", \(kf.values?.count ?? 0) keyframes" }
                    lines.append(desc)
                }
            }
            // sammenlign armens keyframe midt i overgangen med analytisk værdi
            if let kf = layer.debugLayers.first(where: { $0.0 == "arm" })?.1.animation(forKey: "arm") as? CAKeyframeAnimation,
               let vals = kf.values as? [Double], let times = kf.keyTimes?.map(\.doubleValue) {
                let mid = vals.count / 3
                let tm = t + times[mid] * kf.duration
                lines.append(String(format: "  arm-keyframe %d: %.4f rad, analytisk %.4f rad", mid, -vals[mid], a.pose(at: tm).armAngle))
            }
        }
        // Rulletekst: CA-animation mens der spilles, ingen ved pause.
        let mq = MarqueeNSView(frame: NSRect(x: 0, y: 0, width: 170, height: 20))
        let strip = MarqueeStrip(text: "En meget lang sangtitel der slet ikke kan være på én linje", size: 15, dark: true, scale: 2)
        mq.update(strip: strip, textWidth: 420, height: 20, active: true)
        lines.append("Rulletekst spiller: animationer = \(mq.debugAnimationKeys)")
        mq.update(strip: strip, textWidth: 420, height: 20, active: false)
        lines.append("Rulletekst pause: animationer = \(mq.debugAnimationKeys)")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
    }
}

extension SnapshotRenderer {
    // MARK: Layout-tjek (målt i pixels)

    /// Tegner kun ét element (probe) på gennemsigtig baggrund @4x og finder dets synlige kanter (blæk), i punkter.
    static func inkRect(_ s: Scene) -> CGRect? {
        let scale: CGFloat = 4
        let renderer = ImageRenderer(content: scene(s).environment(\.displayScale, scale))
        renderer.scale = scale
        guard let img = renderer.cgImage, let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
        let alphaIndex: Int = {
            switch img.alphaInfo {
            case .premultipliedFirst, .first, .noneSkipFirst: return 0
            default: return bpp - 1
            }
        }()
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<img.height {
            for x in 0..<img.width where p[y * bpr + x * bpp + alphaIndex] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    static func layoutCheck(_ dir: URL) {
        // Titel med flade versaler, så blækkets overkant = versalhøjden.
        var track = np(0, progress: 0.35, at: 0, app: NowPlaying.BundleID.music)
        track.title = "HEJ VERDEN"
        var lines: [String] = ["Layout-tjek (målt på synligt blæk @4x, punkter fra widgettens øverste venstre hjørne)",
                               "Tolerance: 0,5 pt", ""]
        var failures = 0
        func check(_ label: String, _ value: CGFloat?, _ expected: CGFloat) {
            guard let value else { lines.append("  ?  \(label): ikke fundet"); failures += 1; return }
            let ok = abs(value - expected) <= 0.5
            if !ok { failures += 1 }
            lines.append(String(format: "  %@ %@: %.2f (forventet %.2f, afvigelse %+.2f)", ok ? "OK" : "FEJL", label, value, expected, value - expected))
        }
        for size in WidgetSize.allCases {
            let base = Scene(name: "probe", events: [(0, track)], time: 4, size: size)
            func r(_ name: String) -> CGRect? { var s = base; s.probe = name; return inkRect(s) }
            let body = WidgetMetrics.bodySize(for: size)
            lines.append("\(size.title) (\(Int(body.width))×\(Int(body.height))):")
            let krop = r("krop")
            if let k = krop { lines.append(String(format: "     krop: x %.2f–%.2f, y %.2f–%.2f", k.minX, k.maxX, k.minY, k.maxY)) }
            switch size {
            case .small:
                check("krop venstre", krop?.minX, Layout.objectInset)
                check("krop top", krop?.minY, Layout.objectInset)
                check("krop højre", krop?.maxX, body.width - Layout.objectInset)
                check("krop bund", krop?.maxY, body.height - Layout.objectInset)
                let g = TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: Layout.objectRadius)
                check("pladens centrum (lodret) = kroppens midte", g.center.y, 74)
                check("luft armbase → højre kant = luft LED → bund (gitter)", g.deck.maxX - (g.pivot.x + g.basePlateRadius),
                      g.deck.maxY - (g.ledCenter.y + g.speedButtonRadius))
            case .medium:
                let col = WidgetView.mediumColumn(body)
                check("krop venstre", krop?.minX, Layout.objectInset)
                check("krop top", krop?.minY, Layout.objectInset)
                check("krop bund", krop?.maxY, body.height - Layout.objectInset)
                check("titel versaltop = krop top + 8", r("titel")?.minY, Layout.padding)
                check("titel venstre = kolonne", r("titel")?.minX, col.x)
                check("kildeikon venstre = kolonne", r("ikon")?.minX, col.x)
                check("forrige (blæk) venstre = kolonne", r("forrige")?.minX, col.x)
                check("fremdrift venstre = kolonne", r("fremdrift")?.minX, col.x)
                check("fremdrift højre = 16 pt fra kant", r("fremdrift")?.maxX, body.width - Layout.padding)
                check("næste (blæk) højre = 16 pt fra kant", r("næste")?.maxX, body.width - Layout.padding)
                check("afspil bund = krop bund − 8", r("afspil")?.maxY, body.height - Layout.padding)
                if let a = r("afspil"), let f = r("forrige"), let n = r("næste") {
                    check("forrige lodret midte = afspil midte", f.midY, a.midY)
                    check("næste lodret midte = afspil midte", n.midY, a.midY)
                    check("afspil vandret midte = kolonnens midte", a.midX, col.x + col.width / 2)
                }
            case .large:
                let panel = WidgetView.panelRect(body)
                let deck = WidgetView.largeDeck(body)
                check("krop fylder widgetten (venstre)", krop?.minX, 0)
                check("krop fylder widgetten (bund)", krop?.maxY, body.height)
                check("infobjælke venstre = 8", r("panel#ramme")?.minX, Layout.objectInset)
                check("infobjælke højre = 8 fra kant", r("panel#ramme")?.maxX, body.width - Layout.objectInset)
                check("infobjælke bund = 8 fra kant", r("panel#ramme")?.maxY, body.height - Layout.objectInset)
                check("titel versaltop = bjælke top + 16", r("titel")?.minY, panel.minY + Layout.padding)
                check("titel venstre = bjælke + 16", r("titel")?.minX, panel.minX + Layout.padding)
                check("kildeikon venstre = bjælke + 16", r("ikon")?.minX, panel.minX + Layout.padding)
                check("tid (start) ramme venstre = bjælke + 16", r("tid-start#ramme")?.minX, panel.minX + Layout.padding)
                check("tid (slut) ramme højre = bjælke − 16", r("tid-slut#ramme")?.maxX, panel.maxX - Layout.padding)
                check("afspil bund = bjælke bund − 16", r("afspil")?.maxY, panel.maxY - Layout.padding)
                check("afspil vandret midte = widgettens midte", r("afspil")?.midX, body.width / 2)
                let g = TurntableGeometry(size: body, cornerRadius: WidgetMetrics.cornerRadius, deck: deck)
                let massMid = ((g.center.x - g.platterRadius) + (g.pivot.x + g.basePlateRadius)) / 2
                check("plade+arm vandret midte = widgettens midte", massMid, body.width / 2)
                check("dæk lodret midte = midt i det synlige over bjælken", deck.midY, panel.minY / 2)
            default: break
            }
            lines.append("")
        }
        lines.insert(failures == 0 ? "ALT FLUGTER (inden for 0,5 pt)" : "\(failures) AFVIGELSER", at: 0)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("layout-tjek.txt"), atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
    }

    // MARK: Stor "Helt træ" – endelig

    static func largeFinal(_ dir: URL) {
        let music = NowPlaying.BundleID.music
        var scenes: [Scene] = []
        for theme in TurntableTheme.allCases {
            for dark in [true, false] {
                scenes.append(Scene(name: "A-\(theme.rawValue)", events: [(0, np(theme == .auto ? 1 : 0, progress: 0.42, at: 0, app: music))],
                                    time: 4, size: .large, theme: theme, dark: dark,
                                    caption: "\(theme.title) · \(dark ? "mørk" : "lys")"))
            }
        }
        let problem = SourceAccessProblem(bundleID: NowPlaying.BundleID.spotify, message: "Giv adgang til Spotify i Systemindstillinger")
        scenes += [
            Scene(name: "A-pause", events: [(0, np(0, playing: false, progress: 0.42, at: 0, app: music))], time: 4, size: .large,
                  caption: "pause · mørk"),
            Scene(name: "A-pause-lys", events: [(0, np(1, playing: false, progress: 0.42, at: 0, app: music))], time: 4, size: .large,
                  theme: .aluminium, dark: false, caption: "pause · Aluminium · lys"),
            Scene(name: "A-intet", events: [(0, np(0, progress: 0.4, at: 0)), (1, nil)], time: 4, size: .large, caption: "intet spiller · mørk"),
            Scene(name: "A-intet-lys", events: [(0, nil)], time: 4, size: .large, dark: false, caption: "intet spiller · lys"),
            Scene(name: "A-adgang", events: [(0, nil)], time: 4, size: .large, problem: problem, caption: "manglende adgang"),
            Scene(name: "A-daempet", events: [(0, np(0, progress: 0.42, at: 0, app: music))], time: 4, size: .large, dim: 1, desktop: true,
                  caption: "dæmpet (100 %)"),
            Scene(name: "A-lang", events: [(0, np(2, progress: 0.2, at: 0, app: music))], time: 4, size: .large, marqueePhase: 0.3,
                  caption: "lang titel (rulletekst) · uden cover"),
            Scene(name: "A-45", events: [(0, np(0, progress: 0.42, at: 0, app: music))], time: 4, size: .large, speed: .rpm45,
                  caption: "45 aktiv"),
        ]
        sheet("stor-A-endelig", scenes, dir: dir, columns: 4, scale: 3)
    }

    // MARK: Før/efter for Mellem og Lille

    static func beforeAfter(_ dir: URL) {
        let music = NowPlaying.BundleID.music
        let after: [Scene] = [
            Scene(name: "efter-mellem", events: [(0, np(0, progress: 0.35, at: 0, app: music))], time: 4, caption: "EFTER · Mellem"),
            Scene(name: "efter-mellem-lys", events: [(0, np(1, playing: false, progress: 0.35, at: 0, app: music))], time: 4, dark: false,
                  caption: "EFTER · Mellem, pause, lys"),
            Scene(name: "efter-lille", events: [(0, np(0, progress: 0.35, at: 0, app: music))], time: 4, size: .small, hover: true,
                  caption: "EFTER · Lille, mus over"),
        ]
        var befores: [(String, NSImage)] = []
        if let dirPath = ProcessInfo.processInfo.environment["PLADESPILLER_BEFORE_DIR"] {
            for (file, caption) in [("widget-medium.png", "FØR · Mellem"), ("widget-small.png", "FØR · Lille")] {
                if let img = NSImage(contentsOf: URL(fileURLWithPath: dirPath).appendingPathComponent(file)) { befores.append((caption, img)) }
            }
        }
        let view = VStack(alignment: .leading, spacing: 18) {
            if !befores.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(befores.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Image(nsImage: befores[i].1).resizable().interpolation(.high)
                                .frame(width: befores[i].1.size.width / 2, height: befores[i].1.size.height / 2)
                            Text(befores[i].0).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.85))
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(after.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        scene(after[i])
                        Text(after[i].caption).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.85))
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.30))
        write(view, to: dir.appendingPathComponent("polish-foer-efter.png"), scale: 3)
    }
}

/// Et skrivebord bag den dæmpede, gennemsigtige flade: farverigt og sløret (som macOS' sløring bag widgets).
private struct FakeDesktop: View {
    let dark: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.16, blue: 0.32), Color(red: 0.35, green: 0.18, blue: 0.30)]
                                        : [Color(red: 0.62, green: 0.76, blue: 0.92), Color(red: 0.95, green: 0.80, blue: 0.70)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(dark ? Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.5) : Color.white.opacity(0.7))
                .frame(width: 160).offset(x: 60, y: -40).blur(radius: 30)
        }
    }
}

/// En kilde med en fast tilstand (kun snapshots).
private final class FixedSource: NowPlayingSource {
    let bundleID = NowPlaying.BundleID.mock
    let current: NowPlaying?
    let lastChange = Date()
    var onChange: (() -> Void)?
    init(_ current: NowPlaying?) { self.current = current }
    func start() { onChange?() }
    func stop() {}
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
}
