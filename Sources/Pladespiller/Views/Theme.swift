import AppKit
import CoreGraphics

/// Udseendet af pladespillerens krop. Nyt tema = ny `PlinthMaterial` + en case i `TurntableStyle.make`.
enum PlinthMaterial: Hashable {
    case wood(WoodSpecies)
    case aluminium
    case black
    /// Mat lakeret i en farve (tema "Auto": udledt af coveret).
    case matte(r: Float, g: Float, b: Float)
}

enum WoodSpecies: String, Hashable {
    case walnut, oak
}

struct TurntableStyle: Hashable {
    var plinth: PlinthMaterial
    /// Basisplade under armen og knapper: lys eller mørk metal.
    var darkHardware: Bool

    /// Træsort for tema Træ. Kan ændres når brugeren har valgt (valnød eller lys eg).
    static var woodSpecies: WoodSpecies = .walnut

    static func make(theme: TurntableTheme, artwork: NSImage?) -> TurntableStyle {
        switch theme {
        case .wood: TurntableStyle(plinth: .wood(woodSpecies), darkHardware: false)
        case .aluminium: TurntableStyle(plinth: .aluminium, darkHardware: true)
        case .black: TurntableStyle(plinth: .black, darkHardware: false)
        case .auto:
            if let artwork, let cg = Drawing.cgImage(artwork) {
                TurntableStyle(plinth: autoMaterial(from: Drawing.averageColor(cg)), darkHardware: false)
            } else {
                TurntableStyle(plinth: .black, darkHardware: false)
            }
        }
    }

    /// Dæmpet, mat lakfarve ud fra coverets gennemsnitsfarve.
    static func autoMaterial(from c: SIMD3<Float>) -> PlinthMaterial {
        let ns = NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        let out = NSColor(hue: hue, saturation: min(sat * 0.85, 0.65), brightness: min(max(bri * 0.8, 0.22), 0.58), alpha: 1)
            .usingColorSpace(.sRGB) ?? ns
        // Rund af, så små forskelle i coveret deler billede i cachen.
        func q(_ v: CGFloat) -> Float { (Float(v) * 32).rounded() / 32 }
        return .matte(r: q(out.redComponent), g: q(out.greenComponent), b: q(out.blueComponent))
    }
}

/// Tegner kroppen: materiale, lys, kant og de faste detaljer (armens fod, armstøtte, knapper, LED-fatning).
enum PlinthRenderer {
    static func image(_ g: TurntableGeometry, style: TurntableStyle, scale: CGFloat) -> CGImage? {
        let texture = materialTexture(style.plinth, size: g.size, h: g.h, scale: scale)
        return Drawing.image(size: g.size, scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: g.size)
            let shape = CGPath(roundedRect: rect, cornerWidth: g.cornerRadius, cornerHeight: g.cornerRadius, transform: nil)
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            if let texture { drawUpright(ctx, texture, in: rect) }
            lighting(ctx, rect: rect, material: style.plinth)
            ctx.restoreGState()
            bevel(ctx, rect: rect, radius: g.cornerRadius, material: style.plinth)
            details(ctx, g, style: style, scale: scale)
        }
    }

    /// CGImage tegnet i en y-nedad-kontekst skal vendes for at stå rigtigt.
    static func drawUpright(_ ctx: CGContext, _ img: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    // MARK: Materialer (pixel for pixel, én gang pr. størrelse)

    static func materialTexture(_ m: PlinthMaterial, size: CGSize, h: CGFloat, scale: CGFloat) -> CGImage? {
        let k = Float(148 / h)   // tekstur i samme tæthed som på lille størrelse
        switch m {
        case .wood(let species):
            let n = ValueNoise(seed: 7), n2 = ValueNoise(seed: 31), n3 = ValueNoise(seed: 101)
            let (base, dark, bandAmt): (SIMD3<Float>, SIMD3<Float>, Float) = switch species {
            case .walnut: (SIMD3(0.47, 0.30, 0.18), SIMD3(0.24, 0.13, 0.07), 0.42)
            case .oak: (SIMD3(0.82, 0.67, 0.48), SIMD3(0.60, 0.43, 0.26), 0.38)
            }
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let u = x * k, v = y * k
                // Fin, næsten lige åre langs kroppen med lidt bugtning; hver årering har sin egen styrke.
                let warp = (n.fbm(u * 0.008, v * 0.030, octaves: 3) - 0.5) * 3.2
                let rings = v * 0.19 + warp + 0.25 * sin(u * 0.009 + v * 0.01)
                let idx = rings.rounded(.down)
                let ph = rings - idx
                let lineStrength = 0.35 + 0.65 * n3.hash(Int32(idx), 3)
                let band = pow(0.5 + 0.5 * cos(ph * 2 * .pi), 6) * lineStrength
                let late = smoothstep(0.35, 0.9, ph) * 0.35
                let fiber = n2.value(u * 0.05, v * 2.4) - 0.5
                let fiber2 = n2.value(u * 0.012 + 40, v * 0.9) - 0.5
                let pore = smoothstep(0.86, 0.98, n3.value(u * 0.7, v * 5.0))
                let tone = n.fbm(u * 0.004 + 13, v * 0.015, octaves: 2)
                let amount = bandAmt * band + 0.18 * late * bandAmt + 0.14 * fiber + 0.12 * fiber2 + 0.18 * pore
                var c = mix(base, dark, min(1, max(0, amount + 0.08)))
                c *= 0.90 + 0.20 * tone
                return SIMD4(c.x, c.y, c.z, 1)
            }
        case .aluminium:
            let n = ValueNoise(seed: 3), n2 = ValueNoise(seed: 17)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let u = x * k, v = y * k
                let brush = (n.value(u * 0.015, v * 2.6) - 0.5) * 0.06 + (n2.value(u * 0.25, v * 9) - 0.5) * 0.035
                let gch = 0.76 + brush
                return SIMD4(gch, gch, gch * 1.015, 1)
            }
        case .black:
            let n = ValueNoise(seed: 5)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let gch: Float = 0.072 + (n.value(x * k * 0.8, y * k * 0.8) - 0.5) * 0.008
                return SIMD4(gch, gch, gch * 1.04, 1)
            }
        case let .matte(r, g, b):
            let n = ValueNoise(seed: 9)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let t = 1 + (n.value(x * k * 0.9, y * k * 0.9) - 0.5) * 0.03
                return SIMD4(r * t, g * t, b * t, 1)
            }
        }
    }

    // MARK: Lys og kant

    static func lighting(_ ctx: CGContext, rect: CGRect, material: PlinthMaterial) {
        // Lys fra øverst til venstre.
        let strength: CGFloat = switch material {
        case .black: 0.10
        case .aluminium: 0.16
        default: 0.10
        }
        Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                     Drawing.gradient([(0, Drawing.gray(1, strength)), (0.5, Drawing.gray(1, 0)), (1, Drawing.gray(0, 0.16))]),
                     from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        if case .black = material {
            // Blank lak: en blød diagonal glans.
            Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                         Drawing.gradient([(0.0, Drawing.gray(1, 0)), (0.30, Drawing.gray(1, 0.07)), (0.36, Drawing.gray(1, 0.0)),
                                           (0.62, Drawing.gray(1, 0.0)), (0.68, Drawing.gray(1, 0.035)), (0.74, Drawing.gray(1, 0))]),
                         from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }

    static func bevel(_ ctx: CGContext, rect: CGRect, radius: CGFloat, material: PlinthMaterial) {
        let r = rect.insetBy(dx: 0.6, dy: 0.6)
        let inner = CGPath(roundedRect: r, cornerWidth: max(0, radius - 0.6), cornerHeight: max(0, radius - 0.6), transform: nil)
        let hi: CGFloat = if case .black = material { 0.22 } else { 0.32 }
        Drawing.stroke(ctx, inner, width: 1.0,
                       Drawing.gradient([(0, Drawing.gray(1, hi)), (0.45, Drawing.gray(1, 0.05)), (1, Drawing.gray(0, 0.35))]),
                       from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
    }

    // MARK: Faste detaljer

    static func details(_ ctx: CGContext, _ g: TurntableGeometry, style: TurntableStyle, scale: CGFloat) {
        // CG-skygger ignorerer CTM: forskydning i pixels med y opad.
        func shadowAt(_ dx: CGFloat, _ dy: CGFloat, blur: CGFloat, _ color: CGColor) {
            ctx.setShadow(offset: CGSize(width: dx * scale, height: -dy * scale), blur: blur * scale, color: color)
        }
        let h = g.h
        let shadow = Drawing.gray(0, 0.45)

        // Armens basisplade
        let p = g.pivot, br = g.basePlateRadius
        ctx.saveGState()
        shadowAt(h * 0.004, h * 0.008, blur: h * 0.02, shadow)
        ctx.addPath(Drawing.circle(p, br)); ctx.setFillColor(Drawing.gray(0.5)); ctx.fillPath()
        ctx.restoreGState()
        let plate = style.darkHardware
            ? Drawing.gradient([(0, Drawing.gray(0.30)), (1, Drawing.gray(0.12))])
            : Drawing.gradient([(0, Drawing.gray(0.90)), (0.5, Drawing.gray(0.70)), (1, Drawing.gray(0.50))])
        Drawing.fill(ctx, Drawing.circle(p, br), plate, from: CGPoint(x: p.x - br, y: p.y - br), to: CGPoint(x: p.x + br, y: p.y + br))
        ctx.addPath(Drawing.circle(p, br * 0.78))
        ctx.setStrokeColor(Drawing.gray(style.darkHardware ? 0.0 : 0.35, 0.5)); ctx.setLineWidth(max(0.5, h * 0.003)); ctx.strokePath()
        ctx.addPath(Drawing.circle(p, br - 0.4))
        ctx.setStrokeColor(Drawing.gray(1, 0.35)); ctx.setLineWidth(0.6); ctx.strokePath()
        // lille anti-skating-knap på pladen
        let knob = CGPoint(x: p.x + br * 0.55, y: p.y + br * 0.55)
        Drawing.fill(ctx, Drawing.circle(knob, br * 0.2),
                     Drawing.gradient([(0, Drawing.gray(0.25)), (1, Drawing.gray(0.05))]),
                     from: CGPoint(x: knob.x, y: knob.y - br * 0.2), to: CGPoint(x: knob.x, y: knob.y + br * 0.2))

        // Armstøtte
        let restP = g.world(CGPoint(x: g.armRestLocalX, y: 0), armAngle: g.restAngle)
        let postR = h * 0.016
        ctx.saveGState()
        shadowAt(h * 0.006, h * 0.010, blur: h * 0.012, shadow)
        ctx.addPath(Drawing.circle(restP, postR)); ctx.setFillColor(Drawing.gray(0.2)); ctx.fillPath()
        ctx.restoreGState()
        Drawing.fill(ctx, Drawing.circle(restP, postR),
                     Drawing.gradient([(0, Drawing.gray(0.55)), (1, Drawing.gray(0.12))]),
                     from: CGPoint(x: restP.x - postR, y: restP.y - postR), to: CGPoint(x: restP.x + postR, y: restP.y + postR))
        // lille gaffel på tværs af røret (to metaltappe)
        let across = CGPoint(x: -sin(g.restAngle), y: cos(g.restAngle))
        for side in [-1.0, 1.0] as [CGFloat] {
            let q = CGPoint(x: restP.x + across.x * postR * 1.15 * side, y: restP.y + across.y * postR * 1.15 * side)
            Drawing.fill(ctx, Drawing.circle(q, postR * 0.42),
                         Drawing.gradient([(0, Drawing.gray(0.9)), (1, Drawing.gray(0.35))]),
                         from: CGPoint(x: q.x - postR * 0.4, y: q.y - postR * 0.4), to: CGPoint(x: q.x + postR * 0.4, y: q.y + postR * 0.4))
        }

        // 33/45-knapper og LED-fatning
        let bR = g.speedButtonRadius
        for (i, c) in g.speedButtons.enumerated() {
            ctx.saveGState()
            shadowAt(0, h * 0.004, blur: h * 0.008, shadow)
            ctx.addPath(Drawing.circle(c, bR)); ctx.setFillColor(Drawing.gray(0.3)); ctx.fillPath()
            ctx.restoreGState()
            Drawing.fill(ctx, Drawing.circle(c, bR),
                         i == 0 ? Drawing.gradient([(0, Drawing.gray(0.92)), (1, Drawing.gray(0.62))])
                                : Drawing.gradient([(0, Drawing.gray(0.80)), (1, Drawing.gray(0.50))]),
                         from: CGPoint(x: c.x, y: c.y - bR), to: CGPoint(x: c.x, y: c.y + bR))
            if h >= 120 {
                let text = i == 0 ? "33" : "45"
                drawText(ctx, text, at: c, size: bR * 0.95, color: NSColor(white: 0.18, alpha: 1), weight: .semibold)
            }
        }
        let led = g.ledCenter, lr = g.ledRadius
        ctx.addPath(Drawing.circle(led, lr * 1.6)); ctx.setFillColor(Drawing.gray(0, 0.35)); ctx.fillPath()
        Drawing.fill(ctx, Drawing.circle(led, lr),
                     Drawing.gradient([(0, Drawing.color(0.30, 0.06, 0.04)), (1, Drawing.color(0.12, 0.02, 0.02))]),
                     from: CGPoint(x: led.x, y: led.y - lr), to: CGPoint(x: led.x, y: led.y + lr))
    }

    static func drawText(_ ctx: CGContext, _ s: String, at c: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attr)
        let b = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: c.x - b.width / 2, y: c.y - b.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
