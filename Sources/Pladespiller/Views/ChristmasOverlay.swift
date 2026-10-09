import AppKit
import QuartzCore
import SwiftUI

/// Julestemning oven på et hvilket som helst tema: en lyskæde med varme pærer langs toppen, der blinker blødt
/// hver for sig, stille faldende sne og et varmt skær foroven. Alt kører i Core Animation (sneen i et
/// `CAEmitterLayer`, blinket som gentagne animationer), så appen bruger ikke CPU på det. I snapshots tegnes en
/// stillestående udgave med de samme pærer og faste snefnug.
struct ChristmasOverlay: View {
    /// 1 i widgetten; større på fuld skærm.
    var scale: CGFloat = 1
    var snow = true

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.windowIsVisible) private var windowVisible

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // varmt skær fra lyskæden
                LinearGradient(colors: [Color(.sRGB, red: 1, green: 0.7, blue: 0.35, opacity: 0.16), .clear],
                               startPoint: .top, endPoint: .init(x: 0.5, y: min(0.35, 60 * scale / max(geo.size.height, 1))))
                if snapshot != nil {
                    Canvas { ctx, size in ChristmasDrawing.drawStatic(ctx, size: size, scale: scale, snow: snow) }
                } else {
                    ChristmasLayers(scale: scale, snow: snow, running: windowVisible)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Fælles mål: lyskædens ledning og pærernes placering (y nedad).
enum ChristmasDrawing {
    static let colors: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.72, 0.30),   // rav
        (0.95, 0.27, 0.22),   // rød
        (0.40, 0.82, 0.45),   // grøn
        (1.00, 0.90, 0.68),   // varm hvid
        (0.50, 0.66, 1.00),   // blå
    ]

    /// Ledningen hænger i buer mellem kroge i toppen.
    static func hooks(width: CGFloat, scale: CGFloat) -> [CGFloat] {
        let n = max(2, Int((width / (86 * scale)).rounded()))
        return (0...n).map { width * CGFloat($0) / CGFloat(n) }
    }

    static func wire(width: CGFloat, scale: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let hs = hooks(width: width, scale: scale), top = 1.5 * scale, sag = 5 * scale
        p.move(to: CGPoint(x: hs[0] - 4, y: top))
        for i in 1..<hs.count {
            let mid = (hs[i - 1] + hs[i]) / 2
            p.addQuadCurve(to: CGPoint(x: hs[i], y: top), control: CGPoint(x: mid, y: top + sag * 2))
        }
        return p
    }

    /// Pærerne: punkt på ledningen, hældning (radianer) og farve.
    static func bulbs(width: CGFloat, scale: CGFloat) -> [(p: CGPoint, angle: CGFloat, color: Int)] {
        let hs = hooks(width: width, scale: scale), top = 1.5 * scale, sag = 5 * scale
        var out: [(CGPoint, CGFloat, Int)] = []
        var k = 0
        for i in 1..<hs.count {
            let a = hs[i - 1], b = hs[i], mid = (a + b) / 2
            for t in [0.2, 0.42, 0.62, 0.82] as [CGFloat] {
                let u = 1 - t
                let x = u * u * a + 2 * u * t * mid + t * t * b
                let y = u * u * top + 2 * u * t * (top + sag * 2) + t * t * top
                let dx = 2 * u * (mid - a) + 2 * t * (b - mid), dy = 2 * u * (sag * 2) + 2 * t * (-sag * 2)
                out.append((CGPoint(x: x, y: y), atan2(dy, dx), k % colors.count))
                k += 1
            }
        }
        return out
    }

    static func bulbSize(_ scale: CGFloat) -> CGSize { CGSize(width: 6 * scale, height: 9 * scale) }

    /// Én pære hængende nedad fra (0,0): mørk sokkel, farvet glas med et lille lys stræk.
    static func drawBulb(_ ctx: CGContext, color c: (CGFloat, CGFloat, CGFloat), scale: CGFloat) {
        let s = bulbSize(scale)
        let cap = CGRect(x: -s.width * 0.3, y: 0, width: s.width * 0.6, height: s.height * 0.28)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: s.width * 0.1, cornerHeight: s.width * 0.1, transform: nil))
        ctx.setFillColor(Drawing.color(0.12, 0.2, 0.13)); ctx.fillPath()
        let glass = CGRect(x: -s.width / 2, y: s.height * 0.22, width: s.width, height: s.height * 0.78)
        ctx.addEllipse(in: glass)
        ctx.setFillColor(Drawing.color(c.0, c.1, c.2)); ctx.fillPath()
        ctx.addEllipse(in: CGRect(x: -s.width * 0.25, y: s.height * 0.34, width: s.width * 0.22, height: s.height * 0.3))
        ctx.setFillColor(Drawing.gray(1, 0.75)); ctx.fillPath()
    }

    static func bulbImage(_ color: Int, scale: CGFloat, pixelScale: CGFloat) -> CGImage? {
        let s = bulbSize(scale)
        return Drawing.image(size: s, scale: pixelScale) { ctx in
            ctx.translateBy(x: s.width / 2, y: 0)
            drawBulb(ctx, color: colors[color], scale: scale)
        }
    }

    static func glowImage(_ color: Int, scale: CGFloat, pixelScale: CGFloat) -> CGImage? {
        let r = 13 * scale, c = colors[color]
        return Drawing.image(size: CGSize(width: r * 2, height: r * 2), scale: pixelScale) { ctx in
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(c.0, c.1, c.2, 0.75)), (0.35, Drawing.color(c.0, c.1, c.2, 0.28)),
                                                     (1, Drawing.color(c.0, c.1, c.2, 0))]),
                                   startCenter: CGPoint(x: r, y: r), startRadius: 0, endCenter: CGPoint(x: r, y: r), endRadius: r, options: [])
        }
    }

    static func flakeImage(pixelScale: CGFloat) -> CGImage? {
        Drawing.image(size: CGSize(width: 8, height: 8), scale: pixelScale) { ctx in
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(1, 0.95)), (0.45, Drawing.gray(1, 0.6)), (1, Drawing.gray(1, 0))]),
                                   startCenter: CGPoint(x: 4, y: 4), startRadius: 0, endCenter: CGPoint(x: 4, y: 4), endRadius: 4, options: [])
        }
    }

    /// Stillestående udgave (snapshots).
    static func drawStatic(_ gctx: GraphicsContext, size: CGSize, scale: CGFloat, snow: Bool) {
        gctx.withCGContext { ctx in
            if snow {
                let n = ValueNoise(seed: 41)
                let count = Int(size.width * size.height / (1500 * scale * scale))
                for i in 0..<count {
                    let x = CGFloat(n.hash(Int32(i), 1)) * size.width, y = CGFloat(n.hash(Int32(i), 2)) * size.height
                    let r = (0.8 + CGFloat(n.hash(Int32(i), 3)) * 1.6) * scale
                    ctx.setFillColor(Drawing.gray(1, 0.35 + CGFloat(n.hash(Int32(i), 4)) * 0.5))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }
            ctx.addPath(wire(width: size.width, scale: scale))
            ctx.setStrokeColor(Drawing.color(0.08, 0.14, 0.09, 0.9)); ctx.setLineWidth(1.1 * scale); ctx.strokePath()
            for (i, b) in bulbs(width: size.width, scale: scale).enumerated() {
                let c = colors[b.color], on = i % 3 != 1
                let r = 13 * scale
                ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.color(c.0, c.1, c.2, on ? 0.7 : 0.3)), (1, Drawing.color(c.0, c.1, c.2, 0))]),
                                       startCenter: CGPoint(x: b.p.x, y: b.p.y + 6 * scale), startRadius: 0,
                                       endCenter: CGPoint(x: b.p.x, y: b.p.y + 6 * scale), endRadius: r, options: [])
                ctx.saveGState()
                ctx.translateBy(x: b.p.x, y: b.p.y)
                ctx.rotate(by: b.angle * 0.5)
                drawBulb(ctx, color: c, scale: scale)
                ctx.restoreGState()
            }
        }
    }
}

/// Den levende udgave: lag i Core Animation.
private struct ChristmasLayers: NSViewRepresentable {
    let scale: CGFloat
    let snow: Bool
    let running: Bool

    func makeNSView(context: Context) -> ChristmasNSView { ChristmasNSView() }

    func updateNSView(_ view: ChristmasNSView, context: Context) {
        view.configure(scale: scale, snow: snow, running: running)
    }
}

final class ChristmasNSView: NSView {
    private let root = CALayer()
    private let emitter = CAEmitterLayer()
    private let wire = CAShapeLayer()
    private var bulbs: [CALayer] = []
    private var built: (CGSize, CGFloat, Bool)?
    private var scale: CGFloat = 1
    private var snow = true
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

    func configure(scale: CGFloat, snow: Bool, running: Bool) {
        self.scale = scale
        self.snow = snow
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
        if let b = built, b.0 == size, b.1 == scale, b.2 == snow { return }
        built = (size, scale, snow)
        let px = max(window?.backingScaleFactor ?? 2, 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds

        // Sne: få, bløde fnug der falder langsomt og driver lidt
        emitter.frame = root.bounds
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: -8)
        emitter.emitterSize = CGSize(width: size.width * 1.2, height: 1)
        let flake = CAEmitterCell()
        flake.contents = ChristmasDrawing.flakeImage(pixelScale: px)
        flake.birthRate = Float(size.width * size.height / (11000 * scale * scale)) + 1
        flake.lifetime = Float(size.height / (16 * scale)) + 2
        flake.velocity = 16 * scale
        flake.velocityRange = 7 * scale
        flake.emissionLongitude = .pi / 2
        flake.emissionRange = 0.35
        flake.scale = 0.32 * scale
        flake.scaleRange = 0.2 * scale
        flake.alphaRange = 0.4
        flake.spinRange = 0.5
        flake.xAcceleration = 1.5 * scale
        emitter.emitterCells = snow ? [flake] : []
        emitter.preservesDepth = false
        if snow { emitter.beginTime = CACurrentMediaTime() - Double(flake.lifetime) }   // allerede sne ved start

        // Lyskæden
        wire.frame = root.bounds
        wire.path = ChristmasDrawing.wire(width: size.width, scale: scale)
        wire.strokeColor = Drawing.color(0.08, 0.14, 0.09, 0.9)
        wire.lineWidth = 1.1 * scale
        bulbs.forEach { $0.removeFromSuperlayer() }
        bulbs = []
        let bs = ChristmasDrawing.bulbSize(scale)
        let n = ValueNoise(seed: 7)
        for (i, b) in ChristmasDrawing.bulbs(width: size.width, scale: scale).enumerated() {
            let glow = CALayer()
            let r = 13 * scale
            glow.frame = CGRect(x: b.p.x - r, y: b.p.y + bs.height * 0.6 - r, width: r * 2, height: r * 2)
            glow.contents = ChristmasDrawing.glowImage(b.color, scale: scale, pixelScale: px)
            glow.contentsScale = px
            let bulb = CALayer()
            bulb.bounds = CGRect(origin: .zero, size: bs)
            bulb.anchorPoint = CGPoint(x: 0.5, y: 0)
            bulb.position = b.p
            bulb.setAffineTransform(CGAffineTransform(rotationAngle: b.angle * 0.5))
            bulb.contents = ChristmasDrawing.bulbImage(b.color, scale: scale, pixelScale: px)
            bulb.contentsScale = px
            // blødt, uafhængigt blink (forskellig takt og fase for hver pære)
            let dur = 1.6 + Double(n.hash(Int32(i), 1)) * 1.8
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.25
            twinkle.toValue = 0.95
            twinkle.duration = dur
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            twinkle.timeOffset = Double(n.hash(Int32(i), 2)) * dur * 2
            glow.add(twinkle, forKey: "twinkle")
            let glass = twinkle.copy() as! CABasicAnimation
            glass.fromValue = 0.7
            glass.toValue = 1
            bulb.add(glass, forKey: "twinkle")
            root.addSublayer(glow)
            root.addSublayer(bulb)
            bulbs += [glow, bulb]
        }
        CATransaction.commit()
    }
}
