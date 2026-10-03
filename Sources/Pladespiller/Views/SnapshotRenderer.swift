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
        var titleStyle: TitleStyle = .ellipsis
        var marqueePhase: Double? = nil
        var caption: String = ""
    }

    static let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static func np(_ i: Int, playing: Bool = true, progress: Double, at t: Double) -> NowPlaying {
        MockNowPlayingSource.sample(i, isPlaying: playing, progress: progress, at: base.addingTimeInterval(t))
    }

    static func run(outputDirectory dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let started = Date()

        // Basis: alle tre størrelser i standardtilstand (bevarer de gamle filnavne).
        for size in WidgetSize.allCases {
            write(scene(Scene(name: "widget-\(size.rawValue)", events: [(0, np(0, progress: 0.3, at: 0))], time: 4, size: size)),
                  to: dir.appendingPathComponent("widget-\(size.rawValue).png"))
        }

        // 1. Afspil: flere vinkler og fremdrifter
        let playing = [0.0, 0.25, 0.5, 0.75].map { dt in
            Scene(name: "afspil-vinkel-\(Int(dt * 100))", events: [(0, np(0, progress: 0.3, at: 0))], time: 4 + dt,
                  caption: String(format: "afspil t=%.2f s", 4 + dt))
        } + [0.0, 0.5, 1.0].map { p in
            Scene(name: "afspil-fremdrift-\(Int(p * 100))", events: [(0, np(1, progress: p, at: 0))], time: 2,
                  caption: "fremdrift \(Int(p * 100)) %")
        }
        sheet("01-afspil", playing, dir: dir, columns: 2)

        // 2. Pause og afspil igen (armen løftes, glider til hvile; omvendt)
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
            Scene(name: "ny-sang-\(t)", events: changeEvents, time: t, caption: String(format: "ny sang +%.2f s", t - 5))
        }
        sheet("03-ny-sang", change, dir: dir, columns: 2)

        // 4. Intet spiller, uden cover, lange titler
        var misc: [Scene] = []
        misc.append(Scene(name: "intet", events: [(0, np(0, progress: 0.4, at: 0)), (1, nil)], time: 4, caption: "intet spiller"))
        misc.append(Scene(name: "intet-lille", events: [(0, nil)], time: 4, size: .small, caption: "intet spiller (lille)"))
        misc.append(Scene(name: "uden-cover", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, caption: "uden cover"))
        misc.append(Scene(name: "uden-cover-lys", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, dark: false, caption: "uden cover, lys"))
        sheet("04-tilstande", misc, dir: dir, columns: 2)

        let titles: [Scene] = [
            Scene(name: "titel-ellipse", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, caption: "A: \"…\" (2 linjer)"),
            Scene(name: "titel-rul-0", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, titleStyle: .marquee, marqueePhase: 0,
                  caption: "B: rulletekst, start"),
            Scene(name: "titel-rul-40", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, titleStyle: .marquee, marqueePhase: 0.4,
                  caption: "B: rulletekst, undervejs"),
            Scene(name: "titel-ellipse-lys", events: [(0, np(2, progress: 0.2, at: 0))], time: 3, dark: false, caption: "A: \"…\", lys"),
        ]
        sheet("05-lange-titler", titles, dir: dir, columns: 2)

        // 5. Størrelser × temaer × lys/mørk
        for dark in [true, false] {
            var scenes: [Scene] = []
            for theme in TurntableTheme.allCases {
                for size in WidgetSize.allCases {
                    scenes.append(Scene(name: "\(size.rawValue)-\(theme.rawValue)", events: [(0, np(theme == .auto ? 1 : 0, progress: 0.3, at: 0))],
                                        time: 4, size: size, theme: theme, dark: dark, caption: "\(theme.title) · \(size.title)"))
                }
            }
            sheet(dark ? "06-temaer-moerk" : "07-temaer-lys", scenes, dir: dir, columns: 3)
        }

        // 6. Store enkeltbilleder til at se detaljer
        write(scene(Scene(name: "stor-trae", events: [(0, np(0, progress: 0.35, at: 0))], time: 4, size: .large)), to: dir.appendingPathComponent("detalje-stor-trae.png"), scale: 3)
        write(scene(Scene(name: "stor-pause", events: [(0, np(1, playing: false, progress: 0.35, at: 0))], time: 4, size: .large)), to: dir.appendingPathComponent("detalje-stor-pause.png"), scale: 3)
        write(scene(Scene(name: "mellem-trae", events: [(0, np(0, progress: 0.35, at: 0))], time: 4)), to: dir.appendingPathComponent("detalje-mellem-trae.png"), scale: 3)
        let oak = TurntableStyle.woodSpecies
        TurntableStyle.woodSpecies = .oak
        write(scene(Scene(name: "mellem-eg", events: [(0, np(0, progress: 0.35, at: 0))], time: 4)), to: dir.appendingPathComponent("variant-lys-eg.png"), scale: 2)
        TurntableStyle.woodSpecies = oak

        // 7. Vinkler som tal for op- og nedbremsning (kontinuitet)
        spinReport(to: dir.appendingPathComponent("spin-vinkler.txt"))
        armReport(to: dir.appendingPathComponent("arm-vinkler.txt"))
        print(String(format: "Snapshots færdige på %.1f s", Date().timeIntervalSince(started)))
    }

    // MARK: Scene → view

    static func pose(for s: Scene) -> TurntablePose {
        var a = TurntableAnimator(geometry: TurntableGeometry(size: CGSize(width: 148, height: 148), cornerRadius: 20))
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
        let settings = Settings(defaults: UserDefaults(suiteName: "pladespiller.snapshots")!)
        settings.size = s.size
        settings.theme = s.theme
        let store = NowPlayingStore(sources: [FixedSource(current(for: s))])
        store.start()
        let body = WidgetMetrics.bodySize(for: s.size)
        return WidgetView()
            .frame(width: body.width, height: body.height)
            .background(s.dark ? Color(white: 0.14) : Color(white: 0.94))
            .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
            .environment(settings)
            .environment(store)
            .environment(\.turntableSnapshot, TurntableSnapshotPose(pose: pose(for: s)))
            .environment(\.titleStyle, s.titleStyle)
            .environment(\.marqueePhase, s.marqueePhase)
            .environment(\.colorScheme, s.dark ? .dark : .light)
            .environment(\.displayScale, 2)
    }

    /// Kontaktark: flere scener i et gitter med billedtekst (så man kan se dem på én gang).
    static func sheet(_ name: String, _ scenes: [Scene], dir: URL, columns: Int) {
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
        write(view, to: dir.appendingPathComponent("\(name).png"))
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
        var lines = ["# t (s)\tvinkel (grader)\thastighed (o/min)\tΔvinkel/Δt (o/min)"]
        var prevAngle: Double?, prevV: Double?
        var maxVJump = 0.0, maxMismatch = 0.0
        var ei = 0
        let dt = 0.02
        var t = 0.0
        while t <= 7.5 + 1e-9 {
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
        let summary = String(format: "Største hastighedsspring mellem to samples (20 ms): %.2f o/min (fuld fart = 33,33). "
                             + "Største afvigelse mellem Δvinkel/Δt og hastighed: %.3f o/min.", maxVJump, maxMismatch)
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
