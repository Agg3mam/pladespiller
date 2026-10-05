import AppKit
import QuartzCore
import SwiftUI

/// Test af LIVE-vejen (QA N1/N2): samme `TurntableNSView` og samme kaldrækkefølge som `LiveTurntable.updateNSView`
/// (configure → update → setDim), i realtid, flere sangskift i træk. Efter hvert skift tegnes præsentationslaget
/// af det lag der faktisk sidder i viewet (`view.layer`), og den synlige etiket genkendes ud fra farven.
/// Køres af `--render-snapshots`; viser intet vindue (et evt. vindue ordnes aldrig frem).
enum LiveSequenceTest {
    struct Step { let name: String; let np: NowPlaying?; let expected: LabelContent }

    static func run(dir: URL) -> [String] {
        var lines: [String] = []
        let size = CGSize(width: 148, height: 148)
        let g = TurntableGeometry(size: size, cornerRadius: 20)
        func np(_ i: Int) -> NowPlaying { MockNowPlayingSource.sample(i, isPlaying: true, progress: 0.1, at: .now) }
        let a = np(0), b = np(1), c = np(2)
        let steps = [Step(name: "A", np: a, expected: LabelContent(a)), Step(name: "B", np: b, expected: LabelContent(b)),
                     Step(name: "C", np: c, expected: LabelContent(c)), Step(name: "intet", np: nil, expected: .blank),
                     Step(name: "A igen", np: a, expected: LabelContent(a)), Step(name: "B igen", np: b, expected: LabelContent(b))]
        let candidates: [(String, LabelContent)] = [("A", LabelContent(a)), ("B", LabelContent(b)), ("C", LabelContent(c)), ("tom", .blank)]
        let refs = candidates.map { ($0.0, labelAverage(TurntableImages.label($0.1, g, 2), g)) }

        var failures = 0
        var frames: [CGImage] = []
        for mode in ["uden vindue", "i vindue der aldrig vises (skjult/occluded)", "med fastfrosne overgange (QA's N2-symptom)"] {
            let view = TurntableNSView(frame: NSRect(origin: .zero, size: size))
            let frozen = mode.hasPrefix("med fastfrosne")
            view.debugFreezeAfterSync = frozen
            var window: NSWindow?
            if mode != "uden vindue" {
                let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false
                w.contentView = view
                window = w
            }
            lines.append("Live-sekvens (\(mode)):")
            for step in steps {
                // Samme rækkefølge som LiveTurntable.updateNSView
                view.configure(geometry: g, style: TurntableStyle.make(theme: .wood, artwork: step.np?.artwork))
                view.update(step.np)
                view.setDim(0)
                if frozen {
                    // Før sikkerhedsnettet: skal vise den GAMLE etiket (beviser at testen fanger fejlen)
                    pump(0.5)
                    if let early = renderPresentation(view) {
                        let seen = labelAverage(early, g, inView: true)
                        let best = refs.min { dist($0.1, seen) < dist($1.1, seen) }!.0
                        lines.append("  før sikkerhedsnet (0,5 s): synlig etiket = \(best)")
                    }
                }
                pump(WidgetMetrics.trackChangeDuration + 0.4)
                guard let img = renderPresentation(view) else { lines.append("  kunne ikke tegne"); continue }
                frames.append(img)
                let seen = labelAverage(img, g, inView: true)
                let best = refs.min { dist($0.1, seen) < dist($1.1, seen) }!.0
                let expectedName = candidates.first { $0.1 == step.expected }!.0
                let ok = best == expectedName
                if !ok { failures += 1 }
                lines.append("  efter \(step.name): synlig etiket = \(best), forventet \(expectedName) \(ok ? "OK" : "FEJL")")
            }
            // N1: dæmpning skal kunne ses i viewets lag
            let before = meanAlpha(renderPresentation(view))
            view.setDim(1)
            pump(WidgetMetrics.dimTransition + 0.3)
            let dimmedImg = renderPresentation(view)
            let after = meanAlpha(dimmedImg)
            if let dimmedImg { frames.append(dimmedImg) }
            let okDim = abs(after / max(before, 0.001) - WidgetMetrics.dimContentOpacity) < 0.05
            if !okDim { failures += 1 }
            lines.append(String(format: "  dæmpning i viewets lag: gennemsnitlig alfa %.2f → %.2f (forhold %.2f, forventet %.2f) %@",
                                before, after, after / max(before, 0.001), WidgetMetrics.dimContentOpacity, okDim ? "OK" : "FEJL"))
            view.setDim(0)
            window?.contentView = nil
            window?.close()
        }
        failures += fullChain(g: g, refs: refs, candidates: candidates, frames: &frames, lines: &lines)
        lines.insert(failures == 0 ? "LIVE-TEST: ALT OK" : "LIVE-TEST: \(failures) FEJL", at: 0)
        saveStrip(frames, to: dir.appendingPathComponent("live-sekvens.png"))
        return lines
    }

    /// Hele kæden som i appen: NSHostingView(WidgetView) ← NowPlayingStore ← MockNowPlayingSource, sang skiftes med nextTrack().
    /// Vinduet ordnes aldrig frem (intet vises). Etiketten måles i det TurntableNSView SwiftUI faktisk har lavet.
    static func fullChain(g: TurntableGeometry, refs: [(String, SIMD3<Float>)], candidates: [(String, LabelContent)],
                          frames: inout [CGImage], lines: inout [String]) -> Int {
        let suite = "pladespiller.livetest.\(ProcessInfo.processInfo.processIdentifier)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: UserDefaults(suiteName: suite)!)
        settings.size = .small
        settings.theme = .wood
        settings.showControls = true      // testen måler etiketten i det klassiske Lille-layout
        let mock = MockNowPlayingSource(scripted: false)
        let store = NowPlayingStore(sources: [mock])
        let body = WidgetMetrics.bodySize(for: .small)
        let host = NSHostingView(rootView: WidgetView().environment(settings).environment(store))
        host.frame = NSRect(origin: .zero, size: body)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: body), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        store.start()
        pump(1.5)
        var failures = 0
        lines.append("Hele kæden (SwiftUI → TurntableNSView, nextTrack):")
        let names = ["A", "B", "C"]
        for step in 0..<5 {
            if step > 0 { mock.nextTrack() }
            pump(WidgetMetrics.trackChangeDuration + 0.5)
            guard let tv = findTurntable(in: host), let img = renderPresentation(tv) else {
                lines.append("  fandt ikke TurntableNSView"); failures += 1; continue
            }
            frames.append(img)
            let seen = labelAverage(img, TurntableGeometry(size: tv.bounds.size, cornerRadius: 20), inView: true)
            let best = refs.min { dist($0.1, seen) < dist($1.1, seen) }!.0
            let expectedName = names[step % 3]
            let ok = best == expectedName
            if !ok { failures += 1 }
            lines.append("  sang \(step + 1) (\(store.current?.title ?? "-")): synlig etiket = \(best), forventet \(expectedName) \(ok ? "OK" : "FEJL")")
        }
        store.stop()
        window.contentView = nil
        window.close()
        return failures
    }

    static func findTurntable(in view: NSView) -> TurntableNSView? {
        if let t = view as? TurntableNSView { return t }
        for sub in view.subviews { if let t = findTurntable(in: sub) { return t } }
        return nil
    }

    /// Lad tiden gå (run loop kører, så CA committer og animationer skrider frem).
    static func pump(_ seconds: Double) {
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Tegner præsentationen (det der vises nu) af viewets eget lag.
    static func renderPresentation(_ view: NSView) -> CGImage? {
        guard let layer = view.layer else { return nil }
        let src = layer.presentation() ?? layer
        let scale: CGFloat = 2
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Drawing.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        src.render(in: ctx)
        return ctx.makeImage()
    }

    /// Gennemsnitsfarve i en ring på etiketten (uafhængig af hvor meget den har drejet).
    static func labelAverage(_ img: CGImage?, _ g: TurntableGeometry, inView: Bool = false) -> SIMD3<Float> {
        guard let img, let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return .zero }
        let bpr = img.bytesPerRow
        let scale = CGFloat(img.width) / (inView ? g.size.width : g.labelRadius * 2)
        let c = inView ? CGPoint(x: g.center.x * scale, y: g.center.y * scale) : CGPoint(x: g.labelRadius * scale, y: g.labelRadius * scale)
        let r = g.labelRadius * scale
        var sum = SIMD3<Float>(0, 0, 0), n: Float = 0
        for k in 0..<72 {
            let a = Double(k) / 72 * 2 * .pi
            for f in [0.45, 0.6, 0.75] {
                let x = Int(c.x + r * f * cos(a)), y = Int(c.y + r * f * sin(a))
                guard x >= 0, y >= 0, x < img.width, y < img.height else { continue }
                let i = y * bpr + x * 4
                let al = max(Float(p[i + 3]), 1)
                sum += SIMD3(Float(p[i]), Float(p[i + 1]), Float(p[i + 2])) / al
                n += 1
            }
        }
        return n > 0 ? sum / n : .zero
    }

    static func dist(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d * d).sum()
    }

    static func meanAlpha(_ img: CGImage?) -> Double {
        guard let img, let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return 0 }
        var s = 0.0, n = 0.0
        for y in stride(from: 0, to: img.height, by: 4) {
            for x in stride(from: 0, to: img.width, by: 4) { s += Double(p[y * img.bytesPerRow + x * 4 + 3]); n += 1 }
        }
        return s / n / 255
    }

    static func saveStrip(_ frames: [CGImage], to url: URL) {
        guard let first = frames.first else { return }
        let w = first.width, h = first.height, gap = 8
        let cols = frames.count / 2 == 0 ? frames.count : (frames.count + 1) / 2
        let rows = (frames.count + cols - 1) / cols
        guard let ctx = CGContext(data: nil, width: cols * (w + gap) + gap, height: rows * (h + gap) + gap, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: Drawing.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.setFillColor(Drawing.gray(0.3)); ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        for (i, f) in frames.enumerated() {
            let col = i % cols, row = i / cols
            ctx.draw(f, in: CGRect(x: gap + col * (w + gap), y: ctx.height - (row + 1) * (h + gap), width: w, height: h))
        }
        if let img = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
