import AppKit
import QuartzCore
import SwiftUI

/// Julestemning oven på et hvilket som helst tema: en lyskæde med store glaspærer langs toppen, der blinker blødt
/// hver for sig, sne med dybde (små fnug langt væk, store bløde tæt på) og et varmt skær foroven. Alt kører i
/// Core Animation (sneen i et `CAEmitterLayer`, blinket som gentagne animationer), så appen bruger ikke CPU på
/// det. I snapshots tegnes en stillestående udgave med de samme pærer og faste snefnug.
struct ChristmasOverlay: View {
    /// 1 i widgetten; større på fuld skærm.
    var scale: CGFloat = 1
    var snow = true
    var lights = true

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.windowIsVisible) private var windowVisible

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if lights {
                    // varmt skær fra lyskæden
                    LinearGradient(colors: [Color(.sRGB, red: 1, green: 0.68, blue: 0.32, opacity: 0.22), .clear],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: min(0.4, 80 * scale / max(geo.size.height, 1))))
                }
                if snapshot != nil {
                    Canvas { ctx, size in ChristmasDrawing.drawStatic(ctx, size: size, scale: scale, snow: snow, lights: lights) }
                } else {
                    ChristmasLayers(scale: scale, snow: snow, lights: lights, running: windowVisible)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Fælles mål og tegninger: lyskædens ledning, pærerne (glas) og snefnug. y nedad.
enum ChristmasDrawing {
    static let colors: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.62, 0.16),   // rav
        (0.92, 0.12, 0.10),   // rød
        (0.14, 0.72, 0.30),   // grøn
        (1.00, 0.86, 0.58),   // varm hvid
        (0.20, 0.42, 0.98),   // blå
    ]

    static let span: CGFloat = 112           // afstand mellem krogene (pt ved scale 1)
    static let sag: CGFloat = 6

    /// Ledningen hænger i buer mellem kroge i toppen.
    static func hooks(width: CGFloat, scale: CGFloat) -> [CGFloat] {
        let n = max(2, Int((width / (span * scale)).rounded()))
        return (0...n).map { width * CGFloat($0) / CGFloat(n) }
    }

    static func wire(width: CGFloat, scale: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let hs = hooks(width: width, scale: scale), top = 1.5 * scale, s = sag * scale
        p.move(to: CGPoint(x: hs[0] - 4, y: top))
        for i in 1..<hs.count {
            let mid = (hs[i - 1] + hs[i]) / 2
            p.addQuadCurve(to: CGPoint(x: hs[i], y: top), control: CGPoint(x: mid, y: top + s * 2))
        }
        return p
    }

    /// Pærerne: punkt på ledningen, hældning (radianer) og farve.
    static func bulbs(width: CGFloat, scale: CGFloat) -> [(p: CGPoint, angle: CGFloat, color: Int)] {
        let hs = hooks(width: width, scale: scale), top = 1.5 * scale, s = sag * scale
        var out: [(CGPoint, CGFloat, Int)] = []
        var k = 0
        for i in 1..<hs.count {
            let a = hs[i - 1], b = hs[i], mid = (a + b) / 2
            for t in [0.16, 0.39, 0.61, 0.84] as [CGFloat] {
                let u = 1 - t
                let x = u * u * a + 2 * u * t * mid + t * t * b
                let y = u * u * top + 2 * u * t * (top + s * 2) + t * t * top
                let dx = 2 * u * (mid - a) + 2 * t * (b - mid), dy = 2 * u * (s * 2) + 2 * t * (-s * 2)
                out.append((CGPoint(x: x, y: y), atan2(dy, dx), k % colors.count))
                k += 1
            }
        }
        return out
    }

    /// En klassisk julepære (C9): sokkel øverst, glasset buler ud og ender i en afrundet spids.
    static func bulbSize(_ scale: CGFloat) -> CGSize { CGSize(width: 10 * scale, height: 17 * scale) }

    static func glassPath(_ s: CGSize) -> CGPath {
        let w = s.width, h = s.height, top = h * 0.3
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -w * 0.27, y: top))
        p.addCurve(to: CGPoint(x: -w * 0.5, y: h * 0.62), control1: CGPoint(x: -w * 0.30, y: h * 0.42), control2: CGPoint(x: -w * 0.5, y: h * 0.48))
        p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -w * 0.5, y: h * 0.80), control2: CGPoint(x: -w * 0.20, y: h * 0.98))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.62), control1: CGPoint(x: w * 0.20, y: h * 0.98), control2: CGPoint(x: w * 0.5, y: h * 0.80))
        p.addCurve(to: CGPoint(x: w * 0.27, y: top), control1: CGPoint(x: w * 0.5, y: h * 0.48), control2: CGPoint(x: w * 0.30, y: h * 0.42))
        p.closeSubpath()
        return p
    }

    /// Én pære hængende nedad fra (0,0). `lit`: tændt (glødende glas med varm kerne) eller slukket (mørkere farvet glas).
    static func drawBulb(_ ctx: CGContext, color c: (CGFloat, CGFloat, CGFloat), scale: CGFloat, lit: Bool) {
        let s = bulbSize(scale), w = s.width, h = s.height
        // sokkel: mørkegrøn plast med riller
        let socket = CGRect(x: -w * 0.3, y: 0, width: w * 0.6, height: h * 0.33)
        let sp = CGPath(roundedRect: socket, cornerWidth: w * 0.12, cornerHeight: w * 0.12, transform: nil)
        Drawing.fill(ctx, sp, Drawing.gradient([(0, Drawing.color(0.05, 0.16, 0.08)), (0.4, Drawing.color(0.16, 0.32, 0.18)), (1, Drawing.color(0.03, 0.10, 0.05))]),
                     from: CGPoint(x: -w * 0.3, y: 0), to: CGPoint(x: w * 0.3, y: 0))
        ctx.setStrokeColor(Drawing.color(0, 0.05, 0.02, 0.6)); ctx.setLineWidth(max(0.4, 0.5 * scale))
        for k in 1...3 {
            let y = socket.minY + socket.height * CGFloat(k) / 4
            ctx.move(to: CGPoint(x: socket.minX + 0.5, y: y)); ctx.addLine(to: CGPoint(x: socket.maxX - 0.5, y: y))
        }
        ctx.strokePath()

        // glasset
        let glass = glassPath(s)
        ctx.saveGState()
        ctx.addPath(glass); ctx.clip()
        let center = CGPoint(x: 0, y: h * 0.64)
        if lit {
            // varm, næsten hvid kerne → mættet farve → mørkere kant (lyset bryder i glasset)
            let core = (min(1, c.0 + 0.55), min(1, c.1 + 0.55), min(1, c.2 + 0.45))
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(core.0, core.1, core.2)), (0.38, Drawing.color(c.0, c.1, c.2)),
                                                     (1, Drawing.color(c.0 * 0.62, c.1 * 0.62, c.2 * 0.62))]),
                                   startCenter: center, startRadius: 0, endCenter: center, endRadius: h * 0.48, options: [.drawsAfterEndLocation])
        } else {
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(c.0 * 0.62, c.1 * 0.62, c.2 * 0.62)), (1, Drawing.color(c.0 * 0.3, c.1 * 0.3, c.2 * 0.3))]),
                                   startCenter: center, startRadius: 0, endCenter: center, endRadius: h * 0.48, options: [.drawsAfterEndLocation])
        }
        // glødetråd skimtes gennem glasset
        ctx.setStrokeColor(Drawing.gray(1, lit ? 0.55 : 0.18)); ctx.setLineWidth(max(0.4, 0.45 * scale))
        ctx.move(to: CGPoint(x: -w * 0.08, y: h * 0.34)); ctx.addLine(to: CGPoint(x: -w * 0.05, y: h * 0.55))
        ctx.move(to: CGPoint(x: w * 0.08, y: h * 0.34)); ctx.addLine(to: CGPoint(x: w * 0.05, y: h * 0.55))
        ctx.strokePath()
        ctx.restoreGState()

        // spejlinger i glasset: et langt, skarpt stræk mod lyset og en lille prik
        let streak = CGMutablePath()
        streak.move(to: CGPoint(x: -w * 0.3, y: h * 0.48))
        streak.addQuadCurve(to: CGPoint(x: -w * 0.16, y: h * 0.86), control: CGPoint(x: -w * 0.38, y: h * 0.72))
        ctx.addPath(streak)
        ctx.setStrokeColor(Drawing.gray(1, lit ? 0.75 : 0.55)); ctx.setLineWidth(max(0.6, 1.1 * scale)); ctx.setLineCap(.round); ctx.strokePath()
        ctx.addEllipse(in: CGRect(x: w * 0.12, y: h * 0.42, width: w * 0.12, height: w * 0.12))
        ctx.setFillColor(Drawing.gray(1, lit ? 0.6 : 0.4)); ctx.fillPath()
        // glaskant
        ctx.addPath(glass)
        ctx.setStrokeColor(Drawing.color(c.0 * 0.35, c.1 * 0.35, c.2 * 0.35, 0.55)); ctx.setLineWidth(max(0.4, 0.5 * scale)); ctx.strokePath()
    }

    static func bulbImage(_ color: Int, scale: CGFloat, pixelScale: CGFloat, lit: Bool) -> CGImage? {
        let s = bulbSize(scale)
        return Drawing.image(size: s, scale: pixelScale) { ctx in
            ctx.translateBy(x: s.width / 2, y: 0)
            drawBulb(ctx, color: colors[color], scale: scale, lit: lit)
        }
    }

    static func glowRadius(_ scale: CGFloat) -> CGFloat { 24 * scale }

    static func glowImage(_ color: Int, scale: CGFloat, pixelScale: CGFloat) -> CGImage? {
        let r = glowRadius(scale), c = colors[color]
        return Drawing.image(size: CGSize(width: r * 2, height: r * 2), scale: pixelScale) { ctx in
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(c.0, c.1, c.2, 0.85)), (0.18, Drawing.color(c.0, c.1, c.2, 0.45)),
                                                     (0.5, Drawing.color(c.0, c.1, c.2, 0.14)), (1, Drawing.color(c.0, c.1, c.2, 0))]),
                                   startCenter: CGPoint(x: r, y: r), startRadius: 0, endCenter: CGPoint(x: r, y: r), endRadius: r, options: [])
        }
    }

    /// Snefnug: blød skive (`blur` 0 = skarpere kant, 1 = helt blød bokeh).
    static func flakeImage(pixelScale: CGFloat, blur: CGFloat) -> CGImage? {
        Drawing.image(size: CGSize(width: 16, height: 16), scale: pixelScale) { ctx in
            let inner = 0.55 - 0.45 * blur
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(1, 1)), (inner, Drawing.gray(1, 0.85 - 0.4 * blur)), (1, Drawing.gray(1, 0))]),
                                   startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
        }
    }

    /// Sneens tre lag: (størrelse i pt, fald i pt/s, synlige fnug pr. 10.000 pt², gennemsigtighed, sløring).
    static let snowLayers: [(size: CGFloat, speed: CGFloat, density: CGFloat, alpha: CGFloat, blur: CGFloat)] = [
        (2.4, 12, 3.2, 0.6, 0.2),      // langt væk: små og langsomme
        (4.2, 22, 1.4, 0.85, 0.35),    // midt i
        (9.0, 40, 0.25, 0.45, 1.0),    // tæt på: store, bløde og hurtige
    ]

    /// Antal synlige fnug i et lag på en flade (færre pr. punkt, når alt er skaleret op).
    static func visibleFlakes(_ l: (size: CGFloat, speed: CGFloat, density: CGFloat, alpha: CGFloat, blur: CGFloat),
                              area: CGSize, scale: CGFloat) -> CGFloat {
        area.width * area.height / 10000 * l.density / (scale * scale)
    }

    /// Stillestående udgave (snapshots).
    static func drawStatic(_ gctx: GraphicsContext, size: CGSize, scale: CGFloat, snow: Bool, lights: Bool) {
        gctx.withCGContext { ctx in
            if snow {
                let n = ValueNoise(seed: 41)
                var i: Int32 = 0
                for layer in snowLayers {
                    let count = Int(visibleFlakes(layer, area: size, scale: scale))
                    for _ in 0..<count {
                        i += 1
                        let x = CGFloat(n.hash(i, 1)) * size.width, y = CGFloat(n.hash(i, 2)) * size.height
                        let r = layer.size * scale * (0.7 + CGFloat(n.hash(i, 3)) * 0.6) / 2
                        let a = layer.alpha * (0.6 + CGFloat(n.hash(i, 4)) * 0.4)
                        ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(1, a)), (0.55 - 0.45 * layer.blur, Drawing.gray(1, a * 0.8)), (1, Drawing.gray(1, 0))]),
                                               startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
                    }
                }
            }
            guard lights else { return }
            ctx.addPath(wire(width: size.width, scale: scale))
            ctx.setStrokeColor(Drawing.color(0.06, 0.13, 0.07, 0.95)); ctx.setLineWidth(1.3 * scale); ctx.strokePath()
            let bs = bulbSize(scale)
            for (i, b) in bulbs(width: size.width, scale: scale).enumerated() {
                let c = colors[b.color], on = i % 4 != 1
                let r = glowRadius(scale), gc = CGPoint(x: b.p.x, y: b.p.y + bs.height * 0.62)
                ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(c.0, c.1, c.2, on ? 0.8 : 0.25)), (0.18, Drawing.color(c.0, c.1, c.2, on ? 0.4 : 0.1)),
                                                         (1, Drawing.color(c.0, c.1, c.2, 0))]),
                                       startCenter: gc, startRadius: 0, endCenter: gc, endRadius: r, options: [])
                ctx.saveGState()
                ctx.translateBy(x: b.p.x, y: b.p.y)
                ctx.rotate(by: b.angle * 0.5)
                drawBulb(ctx, color: c, scale: scale, lit: on)
                ctx.restoreGState()
            }
        }
    }
}

/// Den levende udgave: lag i Core Animation.
private struct ChristmasLayers: NSViewRepresentable {
    let scale: CGFloat
    let snow: Bool
    let lights: Bool
    let running: Bool

    func makeNSView(context: Context) -> ChristmasNSView { ChristmasNSView() }

    func updateNSView(_ view: ChristmasNSView, context: Context) {
        view.configure(scale: scale, snow: snow, lights: lights, running: running)
    }
}

/// Sne og lyskæde som Core Animation-lag. Bruges både i widgetten, på fuld skærm og som sne på skrivebordet.
final class ChristmasNSView: NSView {
    private let root = CALayer()
    private let emitter = CAEmitterLayer()
    private let wire = CAShapeLayer()
    private var bulbs: [CALayer] = []
    private var built: (CGSize, CGFloat, Bool, Bool)?
    private var scale: CGFloat = 1
    private var snow = true
    private var lights = true
    private var running = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(root)
        root.isGeometryFlipped = true                     // y nedad, som tegningerne
        root.addSublayer(emitter)
        root.addSublayer(wire)
        wire.fillColor = nil
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(scale: CGFloat, snow: Bool, lights: Bool, running: Bool) {
        self.scale = scale
        self.snow = snow
        self.lights = lights
        self.running = running
        rebuildIfNeeded()
        emitter.birthRate = running && snow ? 1 : 0
    }

    override func layout() {
        super.layout()
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if let b = built, b.0 == size, b.1 == scale, b.2 == snow, b.3 == lights { return }
        built = (size, scale, snow, lights)
        let px = max(window?.backingScaleFactor ?? 2, 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds

        // Sne i tre dybder: små og langsomme langt væk, store, bløde og hurtige tæt på. Let drift og svaj.
        emitter.frame = root.bounds
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: -20 * scale)
        emitter.emitterSize = CGSize(width: size.width * 1.3, height: 1)
        var cells: [CAEmitterCell] = []
        for (i, l) in ChristmasDrawing.snowLayers.enumerated() {
            let cell = CAEmitterCell()
            cell.contents = ChristmasDrawing.flakeImage(pixelScale: px, blur: l.blur)
            // Fødselsrate = synlige fnug / tiden et fnug er på skærmen (så tætheden er den samme på alle størrelser).
            let onScreen = (size.height + 40 * scale) / (l.speed * scale)
            cell.birthRate = Float(ChristmasDrawing.visibleFlakes(l, area: size, scale: scale) / onScreen)
            cell.lifetime = Float(onScreen * 1.5)
            cell.velocity = l.speed * scale
            cell.velocityRange = l.speed * scale * 0.3
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = 0.25
            cell.scale = l.size * scale / 16
            cell.scaleRange = l.size * scale / 16 * 0.35
            cell.alphaRange = 0.3
            cell.color = NSColor(white: 1, alpha: l.alpha).cgColor
            cell.spin = 0
            cell.spinRange = 1.2
            cell.xAcceleration = (i % 2 == 0 ? 2.5 : -1.5) * scale      // vinden flytter lagene lidt forskelligt
            cell.yAcceleration = 0
            cells.append(cell)
        }
        emitter.emitterCells = snow ? cells : []
        if snow { emitter.beginTime = CACurrentMediaTime() - 60 }       // det sner allerede, når den vises

        // Lyskæden: glaspærer med en tændt og en slukket udgave; den tændte blinker blødt ind og ud.
        bulbs.forEach { $0.removeFromSuperlayer() }
        bulbs = []
        wire.isHidden = !lights
        if lights {
            wire.frame = root.bounds
            wire.path = ChristmasDrawing.wire(width: size.width, scale: scale)
            wire.strokeColor = Drawing.color(0.06, 0.13, 0.07, 0.95)
            wire.lineWidth = 1.3 * scale
            let bs = ChristmasDrawing.bulbSize(scale)
            let n = ValueNoise(seed: 7)
            for (i, b) in ChristmasDrawing.bulbs(width: size.width, scale: scale).enumerated() {
                let r = ChristmasDrawing.glowRadius(scale)
                let glow = CALayer()
                glow.frame = CGRect(x: b.p.x - r, y: b.p.y + bs.height * 0.62 - r, width: r * 2, height: r * 2)
                glow.contents = ChristmasDrawing.glowImage(b.color, scale: scale, pixelScale: px)
                glow.contentsScale = px
                func bulbLayer(lit: Bool) -> CALayer {
                    let l = CALayer()
                    l.bounds = CGRect(origin: .zero, size: bs)
                    l.anchorPoint = CGPoint(x: 0.5, y: 0)
                    l.position = b.p
                    l.setAffineTransform(CGAffineTransform(rotationAngle: b.angle * 0.5))
                    l.contents = ChristmasDrawing.bulbImage(b.color, scale: scale, pixelScale: px, lit: lit)
                    l.contentsScale = px
                    return l
                }
                let off = bulbLayer(lit: false), on = bulbLayer(lit: true)
                // blødt, uafhængigt blink (forskellig takt og fase for hver pære); de fleste er tændt det meste af tiden
                let dur = 1.8 + Double(n.hash(Int32(i), 1)) * 2.4
                let twinkle = CAKeyframeAnimation(keyPath: "opacity")
                twinkle.values = [1, 1, 0.15, 1]
                twinkle.keyTimes = [0, 0.55, 0.75, 1]
                twinkle.duration = dur
                twinkle.repeatCount = .infinity
                twinkle.calculationMode = .cubic
                twinkle.timeOffset = Double(n.hash(Int32(i), 2)) * dur
                glow.add(twinkle, forKey: "twinkle")
                on.add(twinkle, forKey: "twinkle")
                root.addSublayer(glow)
                root.addSublayer(off)
                root.addSublayer(on)
                bulbs += [glow, off, on]
            }
        }
        CATransaction.commit()
    }
}
