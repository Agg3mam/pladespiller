import AppKit
import QuartzCore

/// `--arm-test [mappe]` (køres også af `--render-snapshots`): grib og træk i pickuparmen.
///
/// Syntetiske musehændelser sendes direkte til et `TurntableNSView` (ingen rigtige input-events, vinduet vises aldrig),
/// og en simuleret musikapp svarer som `NowPlayingStore` med forsinkelse: klik → afspil/pause efter 0–150 ms, spol →
/// ny position efter 0–300 ms, og bagefter en "bekræftelse" hvor positionen afviger op til 1 s.
/// Pr. billede (60 og 120 Hz) aflæses det, der VISES (præsentationslaget): armens vinkel og løft, skyggen og pladens
/// rotation – og der tjekkes, at intet springer, dykker eller går den forkerte vej.
enum ArmDragTest {
    // MARK: Scenarier

    /// Et punkt på musens vej: grader fra trykket (i andele af rilleområdet) eller et sted i rillerne (0 = yderst, 1 = inderst,
    /// under 0 / over 1 = ud over kanten).
    enum Mark { case rel(Double), groove(Double) }

    /// Ét greb: tryk ved `press` (s fra start). Musen følger `path` (tid efter trykket → mærke), slip ved `release` (efter trykket).
    struct Gesture {
        var press: Double
        var path: [(Double, Mark)]
        var release: Double
    }

    struct Scenario {
        let name: String
        var playing = true
        var progress = 0.4
        var gestures: [Gesture]
        /// Skal musikken spille bagefter (tryk pauser, træk fortsætter, klik vender)?
        var expectPlaying: Bool
    }

    static func still(_ press: Double, release: Double) -> Gesture { Gesture(press: press, path: [(0, .rel(0))], release: release) }

    static let scenarios: [Scenario] = [
        Scenario(name: "tryk og hold uden træk", gestures: [still(0.4, release: 0.6)], expectPlaying: false),
        Scenario(name: "træk med det samme (0 ms)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.3, .rel(0.3))], release: 0.32)], expectPlaying: true),
        Scenario(name: "træk 16 ms efter tryk",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.016, .rel(0)), (0.316, .rel(0.3))], release: 0.34)],
                 expectPlaying: true),
        Scenario(name: "træk 50 ms efter tryk (midt i løftet)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.05, .rel(0)), (0.35, .rel(-0.3))], release: 0.37)],
                 expectPlaying: true),
        Scenario(name: "langsom start (under 3 pt)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.6, .rel(0.3))], release: 0.65)], expectPlaying: true),
        Scenario(name: "langsomt over hele området (2 s)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.3, .groove(0)), (2.3, .groove(1))], release: 2.35)],
                 expectPlaying: true),
        Scenario(name: "middel (0,5 s)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.1, .groove(1)), (0.6, .groove(0.05))], release: 0.65)],
                 expectPlaying: true),
        Scenario(name: "meget hurtigt (100 ms) og slip",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.1, .groove(0.95))], release: 0.1)], expectPlaying: true),
        Scenario(name: "frem og tilbage",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.25, .groove(0.9)), (0.5, .groove(0.1)), (0.75, .groove(0.9)),
                                                        (1.0, .groove(0.1)), (1.15, .groove(0.6))], release: 1.25)],
                 expectPlaying: true),
        Scenario(name: "ud over yder- og inderkant (klemning)",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.3, .groove(-0.6)), (0.6, .groove(1.6)), (0.9, .groove(0.5))],
                                    release: 1.0)], expectPlaying: true),
        Scenario(name: "slip midt i løftet",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.02, .rel(0)), (0.08, .rel(0.4))], release: 0.09)],
                 expectPlaying: true),
        Scenario(name: "kort klik ved spil", gestures: [still(0.4, release: 0.08)], expectPlaying: false),
        Scenario(name: "kort klik ved pause", playing: false, gestures: [still(0.4, release: 0.08)], expectPlaying: true),
        Scenario(name: "fra hvile (pause) ind over pladen", playing: false,
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.4, .groove(0.5))], release: 0.5)], expectPlaying: false),
        Scenario(name: "fra hvile, langsom start", playing: false,
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.8, .rel(0.4))], release: 0.85)], expectPlaying: false),
        Scenario(name: "grib igen lige efter slip",
                 gestures: [Gesture(press: 0.4, path: [(0, .rel(0)), (0.2, .rel(0.3))], release: 0.25),
                            Gesture(press: 0.95, path: [(0, .rel(0)), (0.3, .rel(-0.4))], release: 0.35)], expectPlaying: true),
        Scenario(name: "klik, og grib armen på vej mod støtten",
                 gestures: [still(0.4, release: 0.08), Gesture(press: 0.75, path: [(0, .rel(0)), (0.3, .groove(0.7))], release: 0.35)],
                 expectPlaying: false),
    ]

    /// Musikappens svartider (s) og hvor meget bekræftelsens position afviger (s).
    struct Replies { let name: String; let click: Double; let seek: Double; let confirm: Double; let offset: Double }
    static let replies: [Replies] = [
        Replies(name: "svar 0/0 ms, bekræft 250 ms +0,4 s", click: 0, seek: 0, confirm: 0.25, offset: 0.4),
        Replies(name: "svar 16/100 ms, bekræft 400 ms −1 s", click: 0.016, seek: 0.1, confirm: 0.4, offset: -1.0),
        Replies(name: "svar 50/300 ms, bekræft 600 ms +1 s", click: 0.05, seek: 0.3, confirm: 0.6, offset: 1.0),
        Replies(name: "svar 150/0 ms, bekræft 350 ms −0,5 s", click: 0.15, seek: 0, confirm: 0.35, offset: -0.5),
    ]

    // MARK: Simuleret musikapp

    /// Som `NowPlayingStore` + en kilde: `shown` er det widgetten får, `app` er sandheden i musikappen.
    final class SimPlayer {
        var shown: NowPlaying
        var app: NowPlaying
        var events: [(at: Double, apply: () -> Void)] = []
        var seeks: [Double] = []
        let replies: Replies
        var onChange: () -> Void = {}

        init(_ np: NowPlaying, replies: Replies) { shown = np; app = np; self.replies = replies }

        private func schedule(_ delay: Double, _ apply: @escaping () -> Void) {
            events.append((CACurrentMediaTime() + delay, apply))
        }

        /// Afspil/pause: appen skifter med det samme; widgetten får svaret efter `click`, bekræftelsen efter `confirm`.
        func click() {
            let date = Date()
            app.position = app.position(at: date); app.positionTimestamp = date; app.isPlaying.toggle()
            schedule(replies.click) { [self] in
                shown.position = shown.position(at: date); shown.positionTimestamp = date; shown.isPlaying.toggle()
            }
            scheduleConfirm()
        }

        func seek(_ fraction: Double) {
            let date = Date(), target = fraction * app.duration
            seeks.append(target)
            app.position = target; app.positionTimestamp = date
            schedule(replies.seek) { [self] in
                shown.position = target; shown.positionTimestamp = date
            }
            scheduleConfirm()
        }

        private func scheduleConfirm() {
            schedule(replies.confirm) { [self] in
                let now = Date()
                var c = app
                c.position = max(0, app.position(at: now) + replies.offset); c.positionTimestamp = now
                shown = c
            }
        }

        /// Kør de svar, der er nået. Som SwiftUI får viewet kun den nyeste tilstand én gang pr. gennemløb.
        func deliver(until t: Double) {
            var changed = false
            while let i = events.indices.filter({ events[$0].at <= t }).min(by: { events[$0].at < events[$1].at }) {
                let e = events.remove(at: i)
                e.apply()
                changed = true
            }
            if changed { onChange() }
        }
    }

    // MARK: Måling

    enum Phase: Equatable { case free, held(Int), dropped(Int) }

    struct Sample {
        var t: Double            // tidspunktet billedet blev regnet ud til (Core Animations ur)
        var mt: Double           // CACurrentMediaTime ved målingen
        var date: Date
        var phase: Phase
        var mouse: Double?       // musens vinkel om armens leje (rad), mens der holdes
        var arm: Double
        var lift: Double
        var shadow: Double
        var record: Double
        /// Pladens vinkel ifølge den bløde bevægelse (animatoren) – det, den viste vinkel skal følge uden spring.
        var idealRecord: Double
    }

    final class Run {
        let scenario: Scenario
        let replies: Replies
        let view: TurntableNSView
        let player: SimPlayer
        let g: TurntableGeometry
        var samples: [Sample] = []
        var gesture = 0
        var pressed = false
        var pressAngle = 0.0
        var lastMouse: Double?
        var releaseInfo: [(arm: Double, date: Date, moved: Bool)] = []
        var lastBegin = 0.0
        var pressTimes: [Double] = []
        var maxLag = 0.0
        /// Forskudt start, så de tunge øjeblikke (tryk, svar) ikke rammer samme billede i alle forløb.
        var offset = 0.0
        init(scenario: Scenario, replies: Replies, view: TurntableNSView, player: SimPlayer, g: TurntableGeometry) {
            self.scenario = scenario; self.replies = replies; self.view = view; self.player = player; self.g = g
        }
    }

    static let size = CGSize(width: 148, height: 148)
    static var clock: () -> Double = { CACurrentMediaTime() }

    // MARK: Kørsel

    /// Returnerer linjer (første linje = resumé) og antal fejl.
    static func run(dir: URL?) -> (lines: [String], failures: Int) {
        var lines: [String] = []
        var failures = 0
        let cursor = TurntableNSView.setCursor
        TurntableNSView.setCursor = { _ in }            // rør ikke brugerens cursor
        defer { TurntableNSView.setCursor = cursor }
        var worst: [String: Double] = [:]
        var csv: [String] = []
        for hz in [60.0, 120.0] {
            // Én svartid ad gangen (alle scenarier samtidig), så hvert billede når at blive målt til tiden.
            var runs: [Run] = []
            var maxGap = 0.0
            for rep in replies {
                let batch = pass(hz: hz, replies: rep)
                for r in batch {
                    for i in 1..<r.samples.count { maxGap = max(maxGap, r.samples[i].t - r.samples[i - 1].t) }
                }
                runs += batch
            }
            let lag = runs.map(\.maxLag).max() ?? 0
            lines.append(String(format: "Måling %d Hz: længste tid mellem to målte billeder %.1f ms; animationerne startede højst %.1f ms efter udregningen",
                                Int(hz), maxGap * 1000, lag * 1000))
            if maxGap > 3 / hz {
                failures += 1
                lines.append("FEJL målingen kunne ikke følge med (over 3 billeder mellem to målinger)")
            }
            for r in runs {
                let issues = check(r, hz: hz, worst: &worst)
                if issues.isEmpty { continue }
                failures += 1
                lines.append("FEJL \(Int(hz)) Hz · \(r.scenario.name) · \(r.replies.name)")
                for i in issues { lines.append("     " + i) }
                if dir != nil { csv.append(dump(r, hz: hz)) }
            }
            let ok = runs.filter { check($0, hz: hz, worst: &worst).isEmpty }.count
            lines.append("\(ok == runs.count ? "OK  " : "FEJL") \(Int(hz)) Hz: \(ok) af \(runs.count) forløb uden fejl "
                         + "(\(scenarios.count) scenarier × \(replies.count) svartider)")
        }
        lines.append("Største målte værdier (alle forløb):")
        for (k, v) in worst.sorted(by: { $0.key < $1.key }) { lines.append(String(format: "  %@: %.3f", k, v)) }
        lines.insert(failures == 0 ? "ARM-TEST: ALT OK" : "ARM-TEST: \(failures) FEJL", at: 0)
        if let dir, !csv.isEmpty {
            try? csv.joined(separator: "\n\n").write(to: dir.appendingPathComponent("arm-test-fejl.csv"), atomically: true, encoding: .utf8)
        }
        return (lines, failures)
    }

    /// Alle scenarier × svartider samtidig (hvert sit view) i ét usynligt vindue, med ét billede pr. 1/hz s.
    static func pass(hz: Double, replies rep: Replies) -> [Run] {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = container
        defer { window.contentView = nil; window.close() }

        // Ur: et lag der bevæger sig 1 punkt pr. sekund. Aflæst i samme øjeblik som armen giver det præcise tidspunkt,
        // Core Animation regnede billedet ud til.
        container.wantsLayer = true
        let clock = CALayer()
        container.layer?.addSublayer(clock)
        let tick = CABasicAnimation(keyPath: "position.x")
        tick.fromValue = 0
        tick.toValue = 100_000
        tick.duration = 100_000
        clock.add(tick, forKey: "ur")
        CATransaction.flush()
        let clockStart = clock.animation(forKey: "ur")?.beginTime ?? CACurrentMediaTime()
        Self.clock = { (clock.presentation()?.position.x).map { clockStart + Double($0) } ?? CACurrentMediaTime() }
        defer { Self.clock = { CACurrentMediaTime() } }

        let g = TurntableGeometry(size: size, cornerRadius: 20, flat: true)
        let style = TurntableStyle.make(theme: .flat, artwork: nil)
        var runs: [Run] = []
        // Først alle views ind i vinduet, og lad run loop'en sætte lagene på plads: animationer på et lag, der endnu
        // ikke hænger i vinduets lagtræ, starter først, når det kommer det (og så ville de starte for sent).
        let views = scenarios.map { _ in TurntableNSView(frame: NSRect(origin: .zero, size: size)) }
        for v in views { container.addSubview(v) }
        wait(until: CACurrentMediaTime() + 0.05)
        for (s, view) in zip(scenarios, views) {
            let np = MockNowPlayingSource.sample(0, isPlaying: s.playing, progress: s.progress, at: .now)
            let player = SimPlayer(np, replies: rep)
            let run = Run(scenario: s, replies: rep, view: view, player: player, g: g)
            run.offset = Double(runs.count) * 0.043
            // Samme rækkefølge som LiveTurntable.updateNSView
            let deliver = { [unowned view, unowned player] in
                view.configure(geometry: g, style: style)
                view.setSpeed(.calm)
                view.setScrubbing(false)
                view.update(player.shown)
                view.setDim(0)
            }
            player.onChange = deliver
            view.onArmClick = { [unowned player] in player.click() }
            view.onArmSeek = { [unowned player] f in player.seek(f) }
            deliver()
            CATransaction.flush()             // hvert view starter sine animationer med det samme (som i appen)
            runs.append(run)
        }
        wait(until: CACurrentMediaTime() + 0.3)       // billeder og tabeller er lavet; nu måles der

        let start = CACurrentMediaTime()
        let end = runs.map { r in r.offset + r.scenario.gestures.map { $0.press + $0.release }.max()! + 1.7 }.max()!
        var k = 0
        while true {
            let target = start + Double(k) / hz
            k += 1
            wait(until: target)
            let now = CACurrentMediaTime()
            if now - start > end { break }
            for r in runs { step(r, at: now - start - r.offset) }
        }
        return runs
    }

    static func wait(until t: Double) {
        while CACurrentMediaTime() < t {
            let left = t - CACurrentMediaTime()
            if !RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: max(0, left))) {
                Thread.sleep(forTimeInterval: max(0, min(left, 0.001)))
            }
        }
    }

    /// Musens vinkel om leddet → punkt i viewet (på armens rør).
    static func point(_ angle: Double, _ g: TurntableGeometry) -> NSPoint {
        let r = Double(g.tubeLength) * 0.6
        let x = Double(g.pivot.x) + r * cos(angle), y = Double(g.pivot.y) + r * sin(angle)
        return NSPoint(x: x, y: Double(size.height) - y)
    }

    static func event(_ type: NSEvent.EventType, _ view: NSView, _ local: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window?.windowNumber ?? 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    static func angle(_ m: Mark, press: Double, _ g: TurntableGeometry) -> Double {
        let a0 = Double(g.armAngle(forProgress: 0)), a1 = Double(g.armAngle(forProgress: 1))
        switch m {
        case .rel(let f): return press + f * (a1 - a0)
        case .groove(let f): return a0 + f * (a1 - a0)
        }
    }

    /// Musens vinkel `dt` efter trykket (lineært mellem mærkerne).
    static func mouseAngle(_ gst: Gesture, _ dt: Double, press: Double, _ g: TurntableGeometry) -> Double {
        let pts = gst.path.map { ($0.0, angle($0.1, press: press, g)) }
        if dt <= pts[0].0 { return pts[0].1 }
        for i in 1..<pts.count where dt <= pts[i].0 {
            let (t0, v0) = pts[i - 1], (t1, v1) = pts[i]
            return v0 + (v1 - v0) * (dt - t0) / max(t1 - t0, 1e-9)
        }
        return pts.last!.1
    }

    static func step(_ r: Run, at t: Double) {
        let now = CACurrentMediaTime()
        r.player.deliver(until: now)
        guard t >= 0 else { return }
        // Hvert view i sin egen transaktion (et præsentationslag aflæst før låser transaktionens tid).
        CATransaction.flush()
        var phase: Phase = r.samples.last?.phase ?? .free
        if r.gesture < r.scenario.gestures.count {
            let gst = r.scenario.gestures[r.gesture]
            if !r.pressed, t >= gst.press {
                // Tryk præcis på armens rør, der hvor armen ses lige nu.
                CATransaction.flush()
                r.pressAngle = r.view.debugTurntable.visibleArmAngle()
                CATransaction.flush()
                r.pressTimes.append(CACurrentMediaTime())
                r.view.mouseDown(with: event(.leftMouseDown, r.view, point(r.pressAngle, r.g)))
                r.pressed = true
                r.lastMouse = r.pressAngle
                phase = .held(r.gesture)
            } else if r.pressed {
                let dt = min(t - gst.press, gst.release)
                let m = mouseAngle(gst, dt, press: r.pressAngle, r.g)
                if m != r.lastMouse {
                    r.view.mouseDragged(with: event(.leftMouseDragged, r.view, point(m, r.g)))
                    r.lastMouse = m
                }
                if t - gst.press >= gst.release {
                    CATransaction.flush()
                    let held = r.view.debugTurntable.visibleArmAngle()
                    CATransaction.flush()
                    let moved = gst.path.contains { if case .rel(0) = $0.1 { return false } else { return true } }
                    r.view.mouseUp(with: event(.leftMouseUp, r.view, point(m, r.g)))
                    r.releaseInfo.append((held, Date(), moved))
                    r.pressed = false
                    r.lastMouse = nil
                    phase = .dropped(r.gesture)
                    r.gesture += 1
                }
            }
        }
        CATransaction.flush()                 // som når run loop'en committer: animationerne starter "nu"
        let tl = r.view.debugTurntable
        // Hvor længe efter udregningen startede animationerne faktisk (giver et lille hak, hvis det er længe)?
        if let begin = tl.debugLayers.first(where: { $0.0 == "arm" })?.1.animation(forKey: "arm")?.beginTime, begin != r.lastBegin {
            r.lastBegin = begin
            r.maxLag = max(r.maxLag, begin - tl.debugLastStart)
        }
        let arm = tl.visibleArmAngle()
        let ts = clock()
        r.samples.append(Sample(t: ts, mt: CACurrentMediaTime(), date: Date(), phase: phase, mouse: r.pressed ? r.lastMouse : nil, arm: arm,
                                lift: tl.visibleArmLift(), shadow: tl.visibleShadowAngle(), record: tl.visibleRecordAngle(),
                                idealRecord: r.view.debugAnimator?.spin.angle(at: ts) ?? 0))
    }

    // MARK: Tjek

    static let deg = 180 / Double.pi

    /// Alle fejl i ét forløb (tomt = OK). `worst` samler de største målte værdier.
    static func check(_ r: Run, hz: Double, worst: inout [String: Double]) -> [String] {
        var issues: [String: (value: Double, text: String)] = [:]
        func note(_ key: String, _ value: Double) { worst[key] = max(worst[key] ?? 0, value) }
        func fail(_ key: String, _ value: Double, _ text: String) {
            if (issues[key]?.value ?? -1) < value { issues[key] = (value, text) }
        }
        let s = r.samples, g = r.g
        guard s.count > 3 else { return ["for få billeder"] }
        let a0 = Double(g.armAngle(forProgress: 0)), a1 = Double(g.armAngle(forProgress: 1)), rest = Double(g.restAngle)
        let d = r.player.shown.duration
        let t0 = s[0].t
        func rel(_ i: Int) -> String { String(format: "t=%.3f s", s[i].t - t0) }
        // Bekræftelsens afvigelse i grader (armen må gerne rette sig så meget ind)
        let offsetDeg = abs(r.replies.offset) / d * abs(a1 - a0) * deg
        let final = r.player.shown
        func finalAngle(_ date: Date) -> Double {
            final.isPlaying ? Double(g.armAngle(forProgress: final.position(at: date) / d)) : rest
        }

        // Adfærd: tryk pauser, træk fortsætter, klik vender, der spoles kun ved træk.
        if r.player.app.isPlaying != r.scenario.expectPlaying {
            fail("adfærd", 1, "musikken \(r.player.app.isPlaying ? "spiller" : "holder pause") bagefter – forventet det modsatte")
        }
        let movedAny = r.releaseInfo.contains { $0.moved }
        if !movedAny, !r.player.seeks.isEmpty { fail("adfærd-spol", 1, "der blev spolet uden træk") }
        if let last = r.releaseInfo.last(where: { $0.moved }) {
            let f = g.progress(forArmAngle: CGFloat(last.arm))
            let got = r.player.seeks.last ?? -100
            let err = abs(got - f * d)
            if err > 0.5 { fail("adfærd-spol", err, String(format: "spolede til %.1f s, armen blev sluppet ved %.1f s", got, f * d)) }
        }

        // Pladens rotation (afviklet), fart pr. billede
        var rec = [s[0].record]
        for i in 1..<s.count {
            var dr = s[i].record - s[i - 1].record
            dr = atan2(sin(dr), cos(dr))
            rec.append(rec[i - 1] + dr)
        }

        var pressIndex = 0, pressLift = 0.0, pressAngle = 0.0, pressMouse = 0.0, holdTarget = 0.7
        var dropIndex = 0, dropDist = 0.0, minDist = Double.infinity
        let lastGesture = r.scenario.gestures.count - 1
        for i in 1..<s.count {
            let p = s[i], q = s[i - 1]
            let dt = max(p.t - q.t, 1e-4)
            let da = (p.arm - q.arm) * deg, dl = p.lift - q.lift

            // Skyggen følger armen
            let sh = abs(p.shadow - p.arm) * deg
            note("skygge ≠ arm (°)", sh)
            if sh > 0.01 { fail("skygge", sh, String(format: "skyggen står %.2f° fra armen (%@)", sh, rel(i))) }

            // Pladen: følger den bløde op/nedbremsning uden spring (afvigelsen fra den ideelle vinkel må ikke ændre sig
            // brat), og drejer aldrig baglæns. (En fast lille afvigelse er bare tiden fra udregning til visning.)
            let dev = atan2(sin(p.record - p.idealRecord), cos(p.record - p.idealRecord))
            let dev0 = atan2(sin(q.record - q.idealRecord), cos(q.record - q.idealRecord))
            let jump = abs(atan2(sin(dev - dev0), cos(dev - dev0))) * deg
            note("pladen springer i forhold til den bløde bevægelse (°)", jump)
            if ProcessInfo.processInfo.environment["ARM_DEBUG"] != nil, jump > 0.2 {
                print(String(format: "DBG %@ i=%d %@ dev0=%.4f dev=%.4f rec=%.4f/%.4f ideal=%.4f/%.4f dt=%.4f", r.scenario.name, i, rel(i), dev0, dev, q.record, p.record, q.idealRecord, p.idealRecord, dt))
            }
            if jump > 0.35 { fail("plade", jump, String(format: "pladen springer %.2f° %@", jump, rel(i))) }
            let w = (rec[i] - rec[i - 1]) / dt
            if w < -0.05 { fail("plade-baglæns", -w, String(format: "pladen drejer baglæns (%.2f rad/s) %@", w, rel(i))) }

            switch p.phase {
            case .free:
                note("vinkelskridt før greb (°)", abs(da))
                if abs(da) > 0.05 { fail("fri", abs(da), String(format: "armen springer %.2f° før grebet %@", da, rel(i))) }
            case .held(let k):
                let m = p.mouse ?? 0
                if q.phase != .held(k) {
                    // Trykket: armen stopper, hvor den er; løftet fortsætter fra hvor det er
                    // Løftet i selve trykøjeblikket (det kan have været på vej ned siden sidste billede)
                    let lv = i >= 2 ? (q.lift - s[i - 2].lift) / max(q.mt - s[i - 2].mt, 1e-4) : 0
                    let pl = max(0, q.lift + lv * max(0, r.pressTimes[k] - q.mt))
                    pressIndex = i; pressLift = pl; pressAngle = p.arm; pressMouse = m
                    holdTarget = max(0.7, pl)
                    let prevV = i >= 2 ? abs(q.arm - s[i - 2].arm) * deg / max(q.t - s[i - 2].t, 1e-4) : 0
                    let lim = prevV * dt * 1.5 + 0.03
                    note("vinkelspring ved tryk (°)", abs(da))
                    if abs(da) > lim { fail("tryk", abs(da), String(format: "armen springer %.2f° ved trykket %@", da, rel(i))) }
                    let liftLim = 2 * (holdTarget - pressLift) / 0.2 * dt * 1.3 + 0.01
                    if dl > liftLim || dl < -0.003 - abs(q.lift - s[max(0, i - 2)].lift) * 1.5 {
                        fail("tryk-løft", abs(dl), String(format: "løftet springer %.3f ved trykket %@", dl, rel(i)))
                    }
                    continue
                }
                let dm = ((p.mouse ?? 0) - (q.mouse ?? 0)) * deg
                // Ingen spring ud over hvad musen flyttede sig; stille mus = stille arm
                let extra = abs(da) - abs(dm)
                note("vinkelspring ud over musen mens man holder (°)", max(0, extra))
                if extra > 0.02 { fail("hold-spring", extra, String(format: "armen springer %.2f° (musen flyttede %.2f°) %@", da, dm, rel(i))) }
                if abs(da) > 0.02, da * dm < 0 { fail("hold-retning", abs(da), String(format: "armen går %.2f° modsat musen %@", da, rel(i))) }
                // Armen følger musen (klemt til rillerne, eller fra hvor man tog fat)
                let lo = min(a0, pressAngle), hi = max(a1, pressAngle)
                let expected = min(max(pressAngle + (m - pressMouse), lo), hi)
                let lag = abs(p.arm - expected) * deg
                note("armen bag musen mens man holder (°)", lag)
                if lag > 0.05 { fail("hold-følg", lag, String(format: "armen står %.2f° fra musen %@", lag, rel(i))) }
                // Løftet: stiger monotont og blødt, og holder sig så stabilt
                note("løftet dykker mens man holder", max(0, -dl))
                if dl < -0.002 { fail("hold-dyk", -dl, String(format: "løftet dykker %.3f mens man holder %@", dl, rel(i))) }
                let slope = 2 * max(holdTarget - pressLift, 0) / 0.2
                let lim = slope * dt * 1.3 + 0.01
                if dl > lim { fail("hold-løft-spring", dl, String(format: "løftet springer %.3f på ét billede (grænse %.3f) %@", dl, lim, rel(i))) }
                // … og følger præcis den bløde løftekurve fra trykket (ease-out over 0,2 s), også når musen flyttes
                // og musikappens svar lander undervejs (den tidligere fejl: kurven blev lagt om ved hver musebevægelse).
                let sl = min(1, max(0, (p.mt - r.pressTimes[k]) / 0.2))
                let ideal = pressLift + (holdTarget - pressLift) * (1 - (1 - sl) * (1 - sl))
                let curveOff = abs(p.lift - ideal)
                note("løftet afviger fra den bløde kurve mens man holder", curveOff)
                if curveOff > 0.02 {
                    fail("hold-kurve", curveOff, String(format: "løftet er %.3f, den bløde kurve siger %.3f %@", p.lift, ideal, rel(i)))
                }
                if p.t - s[pressIndex].t > 0.2 + 2 / hz {
                    let off = abs(p.lift - holdTarget)
                    note("løftet ustabilt mens man holder", off)
                    if off > 0.005 { fail("hold-stabil", off, String(format: "løftet er %.3f (forventet %.2f) mens man holder %@", p.lift, holdTarget, rel(i))) }
                }
            case .dropped(let k):
                let isLast = k == lastGesture
                if q.phase != .dropped(k) {
                    dropIndex = i
                    let target = isLast ? finalAngle(p.date) : (abs(q.arm - rest) > abs(q.arm - a0) ? a0 : rest)
                    dropDist = max(abs(q.arm - target), abs(q.arm - rest), abs(q.arm - a0), abs(q.arm - a1)) * deg + offsetDeg + 0.5
                    if !isLast { dropDist = max(dropDist, abs(a1 - rest) * deg) }
                    minDist = .infinity
                }
                // Løftet falder blødt og stiger aldrig igen efter slip (i det første billede må det have nået at stige
                // lidt endnu, før der blev sluppet)
                let rise = q.phase == .dropped(k) ? 0 : 2 * max(holdTarget - pressLift, 0) / 0.2 * dt * 1.3
                note("løftet stiger efter slip", max(0, dl - rise))
                if dl > 0.002 + rise { fail("slip-løft-op", dl, String(format: "armen løftes igen (%.3f) efter slip %@", dl, rel(i))) }
                let liftLim = 1.5 * 0.75 / AnimatorConstants.drop * dt * 1.3 + 0.01
                if -dl > liftLim { fail("slip-løft-spring", -dl, String(format: "løftet falder %.3f på ét billede (grænse %.3f) %@", -dl, liftLim, rel(i))) }
                // Vinklen: ingen spring, ingen ryk (pludselig fartændring)
                let vmax = 1.5 * dropDist / AnimatorConstants.drop
                let lim = vmax * dt * 1.3 + 0.03
                note("vinkelskridt efter slip i forhold til grænsen", abs(da) / lim)
                if abs(da) > lim { fail("slip-spring", abs(da), String(format: "armen springer %.2f° på ét billede efter slip (grænse %.2f°) %@", da, lim, rel(i))) }
                if i - dropIndex >= 2 {
                    let v = da / dt, v0 = (q.arm - s[i - 2].arm) * deg / max(q.t - s[i - 2].t, 1e-4)
                    let amax = 6 * dropDist / (AnimatorConstants.drop * AnimatorConstants.drop)
                    let alim = amax * (dt + 1.0 / 120) * 1.3 + 4
                    note("armens fartændring efter slip i forhold til grænsen", abs(v - v0) / alim)
                    if abs(v - v0) > alim {
                        fail("slip-ryk", abs(v - v0), String(format: "armens fart springer %.0f°/s på ét billede (grænse %.0f) %@", v - v0, alim, rel(i)))
                    }
                }
                if isLast {
                    // Glider hen mod den rigtige endelige plads uden at gå den forkerte vej først
                    let dist = abs(p.arm - finalAngle(p.date)) * deg
                    let back = dist - minDist
                    note("armen går den forkerte vej efter slip (°)", max(0, back))
                    if back > 0.03 + offsetDeg {
                        fail("slip-retning", back, String(format: "armen går %.2f° den forkerte vej efter slip %@", back, rel(i)))
                    }
                    minDist = min(minDist, dist)
                }
            }
        }
        // Slutningen: den rigtige plads, nede
        if let p = s.last {
            let err = abs(p.arm - finalAngle(p.date)) * deg
            note("afstand til den rigtige plads til sidst (°)", err)
            if err > 0.05 { fail("slut", err, String(format: "armen ender %.2f° fra %@", err, final.isPlaying ? "rillen" : "støtten")) }
            if p.lift > 0.002 { fail("slut-løft", p.lift, String(format: "armen er stadig løftet (%.3f) til sidst", p.lift)) }
        }
        return issues.sorted { $0.key < $1.key }.map(\.value.text)
    }

    enum AnimatorConstants { static let drop = TurntableAnimator.dropDuration }

    static func dump(_ r: Run, hz: Double) -> String {
        var out = ["# \(Int(hz)) Hz · \(r.scenario.name) · \(r.replies.name)", "t;fase;mus;arm;løft;plade"]
        let t0 = r.samples.first?.t ?? 0
        for s in r.samples {
            let ph: String
            switch s.phase { case .free: ph = "fri"; case .held(let k): ph = "holdt\(k)"; case .dropped(let k): ph = "sluppet\(k)" }
            out.append(String(format: "%.4f;%@;%@;%.4f;%.4f;%.4f", s.t - t0, ph, s.mouse.map { String(format: "%.4f", $0 * deg) } ?? "",
                              s.arm * deg, s.lift, s.record * deg))
        }
        return out.joined(separator: "\n")
    }
}
