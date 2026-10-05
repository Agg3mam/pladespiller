import AppKit
import CoreGraphics

/// Lille LRU-cache til færdigtegnede billeder.
final class ImageCache {
    private let capacity: Int
    private var items: [String: CGImage] = [:]
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    func image(_ key: String, make: () -> CGImage?) -> CGImage? {
        if let hit = items[key] {
            if let i = order.firstIndex(of: key) { order.remove(at: i) }
            order.append(key)
            return hit
        }
        guard let img = make() else { return nil }
        items[key] = img
        order.append(key)
        while order.count > capacity { items[order.removeFirst()] = nil }
        return img
    }

    var count: Int { items.count }
}

/// Hvad der står på etiketten.
enum LabelContent: Equatable {
    case blank
    case cover(key: String, image: NSImage, title: String, artist: String)
    case text(key: String, title: String, artist: String)

    var cacheKey: String {
        switch self {
        case .blank: "blank"
        case .cover(let key, let image, _, _): "cover|\(key)|\(ObjectIdentifier(image).hashValue)"
        case .text(let key, _, _): "text|\(key)"
        }
    }

    init(_ np: NowPlaying?) {
        guard let np else { self = .blank; return }
        let title = TrackStrings.title(np), artist = TrackStrings.artist(np)
        if let art = np.artwork { self = .cover(key: np.trackKey, image: art, title: title, artist: artist) }
        else { self = .text(key: np.trackKey, title: title, artist: artist) }
    }
}

/// Alle billeder til pladespilleren. Tegnes én gang pr. størrelse/skala/tema og genbruges.
/// Kun billederne drejes/flyttes bagefter (riller tegnes aldrig pr. billede).
enum TurntableImages {
    static let shared = ImageCache(capacity: 36)
    /// Seneste par runde etiketter (covers skifter; gamle smides ud, ingen læk).
    static let labels = ImageCache(capacity: 8)   // 4 etiketter + deres gråtonekopier

    static func key(_ name: String, _ g: TurntableGeometry, _ scale: CGFloat) -> String {
        "\(name)|\(g.size.width)x\(g.size.height)|r\(g.cornerRadius)|d\(g.deck.minX),\(g.deck.minY),\(g.deck.width)|f\(g.flat)|@\(scale)"
    }

    static func plinth(_ g: TurntableGeometry, _ style: TurntableStyle, _ scale: CGFloat) -> CGImage? {
        shared.image(key("plinth|\(style)|træ\(WoodTexture.generation)", g, scale)) { PlinthRenderer.image(g, style: style, scale: scale) }
    }

    static func record(_ g: TurntableGeometry, _ palette: FlatPalette?, _ scale: CGFloat) -> CGImage? {
        if let palette {
            return shared.image(key("record|\(palette)", g, scale)) { FlatRecordRenderer.record(g, palette, scale: scale) }
        }
        return shared.image(key("record", g, scale)) { RecordRenderer.record(g, scale: scale) }
    }

    static func platter(_ g: TurntableGeometry, _ palette: FlatPalette?, _ scale: CGFloat) -> CGImage? {
        if palette != nil { return shared.image(key("platterFlat", g, scale)) { FlatRecordRenderer.shadow(g, scale: scale) } }
        return shared.image(key("platter", g, scale)) { RecordRenderer.platter(g, scale: scale) }
    }

    static func sheen(_ g: TurntableGeometry, _ palette: FlatPalette?, _ scale: CGFloat) -> CGImage? {
        if palette != nil { return shared.image(key("sheenFlat", g, scale)) { FlatRecordRenderer.sheen(g, scale: scale) } }
        return shared.image(key("sheen", g, scale)) { RecordRenderer.sheen(g, scale: scale) }
    }

    static func arm(_ g: TurntableGeometry, _ scale: CGFloat) -> CGImage? {
        shared.image(key("arm", g, scale)) { ArmRenderer.image(g, scale: scale, silhouette: false) }
    }

    static func armShadow(_ g: TurntableGeometry, _ scale: CGFloat) -> CGImage? {
        shared.image(key("armShadow", g, scale)) {
            guard let s = ArmRenderer.image(g, scale: scale, silhouette: true) else { return nil }
            // Flad: blødere, lavere skygge (ingen skarpe skygger)
            return Drawing.blurred(s, radiusPx: max(1, g.h * (g.flat ? 0.022 : 0.010) * scale))
        }
    }

    static func speedButton(_ g: TurntableGeometry, _ label: String, active: Bool, _ scale: CGFloat) -> CGImage? {
        shared.image(key("speed\(label)|\(active)", g, scale)) { SpeedButtonRenderer.image(g, label: label, active: active, scale: scale) }
    }

    static func ledGlow(_ g: TurntableGeometry, _ scale: CGFloat) -> CGImage? {
        shared.image(key("led", g, scale)) { RecordRenderer.ledGlow(g, scale: scale) }
    }

    /// Gråtonekopi af et billede fra cachen (dæmpet look).
    static func gray(_ name: String, _ g: TurntableGeometry, _ scale: CGFloat, _ image: CGImage?) -> CGImage? {
        guard let image else { return nil }
        return shared.image(key("gray|" + name, g, scale)) { Drawing.grayscale(image) }
    }

    static func grayLabel(_ content: LabelContent, _ g: TurntableGeometry, _ scale: CGFloat) -> CGImage? {
        guard let color = label(content, g, scale) else { return nil }
        return labels.image("gray|\(content.cacheKey)|\(g.labelRadius)|@\(scale)") { Drawing.grayscale(color) }
    }

    static func label(_ content: LabelContent, _ g: TurntableGeometry, _ scale: CGFloat) -> CGImage? {
        labels.image("\(content.cacheKey)|\(g.labelRadius)|@\(scale)") { LabelRenderer.image(content, g, scale: scale) }
    }
}

// MARK: - Plade, tallerken, refleks

enum RecordRenderer {
    /// Den sorte plade (uden etiket). Kvadrat på 2·pladeradius.
    static func record(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let R = Float(g.recordRadius)
        let side = CGFloat(R * 2)
        let fi = Float(g.grooveInnerRadius) / R, fo = Float(g.grooveOuterRadius) / R
        let fl = Float(g.labelRadius) / R
        let sc = Float(scale)
        // Mellemrum mellem numrene (glattere, mørkere bånd)
        let gaps: [Float] = [0.885, 0.80, 0.735, 0.655, 0.585].map { fi + ($0 - 0.48) / (0.96 - 0.48) * (fo - fi) }
        let gapW: Float = max(0.45, Float(g.h) * 0.0032)
        let n = ValueNoise(seed: 21), n2 = ValueNoise(seed: 77), n3 = ValueNoise(seed: 5)
        return Drawing.pixels(size: CGSize(width: side, height: side), scale: scale) { x, y in
            let dx = x - R, dy = y - R
            let r = (dx * dx + dy * dy).squareRoot()
            let cov = min(max((R - r) * sc + 0.5, 0), 1)
            if cov <= 0 { return .zero }
            let f = r / R
            var l: Float
            if f > fo {
                // Glat kant yderst med afrundet lys kant.
                l = 0.082 + 0.05 * smoothstep(0.988, 0.999, f) - 0.025 * smoothstep(fo, fo + 0.01, f) * (1 - smoothstep(0.98, 0.99, f))
            } else if f >= fi {
                let fine = n.value(r * sc * 0.85, 3.7) - 0.5
                let mid = n2.value(r * 0.30, 11.3) - 0.5
                let ang = atan2(dy, dx)
                let angular = n3.value(cos(ang) * 1.6 + 5 + r * 0.01, sin(ang) * 1.6 + 2) - 0.5
                l = 0.066 + 0.026 * fine + 0.016 * mid + 0.010 * angular
                for gp in gaps {
                    let d = abs(f - gp) * R
                    if d < gapW { l = l + (0.046 - l) * smoothstep(gapW, gapW * 0.35, d) }
                }
                // blød overgang ind/ud af rillerne
                l = l + (0.05 - l) * (1 - smoothstep(fi, fi + 0.012, f)) * 0.6
            } else {
                // Glat, blank zone ved etiketten med et par udløbsriller.
                l = 0.048
                let runout = abs(f - (fl + (fi - fl) * 0.55)) * R
                if runout < 0.35 { l += 0.02 * (1 - runout / 0.35) }
            }
            // Lidt støv, så man kan ane at pladen drejer.
            let cell = n.hash(Int32(x * 0.9), Int32(y * 0.9) &+ 900)
            if cell > 0.9992, f > fl { l += 0.12 }
            l *= cov
            return SIMD4(l, l, l * 1.02, cov)
        }
    }

    /// Den faste tallerken (kant i børstet metal) med skygge. Kvadrat på 2·(radius + margen).
    static func platter(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let m = platterMargin(g), Rp = g.platterRadius
        let side = (Rp + m) * 2
        let c = CGPoint(x: side / 2, y: side / 2)
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: g.h * 0.008 * scale, height: -g.h * 0.016 * scale), blur: g.h * 0.045 * scale,
                          color: Drawing.gray(0, 0.6))
            ctx.addPath(Drawing.circle(c, Rp)); ctx.setFillColor(Drawing.gray(0.3)); ctx.fillPath()
            ctx.restoreGState()
            if let rim = rimTexture(g, side: side, scale: scale) {
                PlinthRenderer.drawUpright(ctx, rim, in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            // fine riller i kanten (strobe-agtig) og mørk kant
            ctx.addPath(Drawing.circle(c, Rp - 0.4)); ctx.setStrokeColor(Drawing.gray(0, 0.45)); ctx.setLineWidth(0.8); ctx.strokePath()
            ctx.addPath(Drawing.circle(c, (Rp + g.recordRadius) / 2)); ctx.setStrokeColor(Drawing.gray(0, 0.18)); ctx.setLineWidth(0.4); ctx.strokePath()
            // gummimåtte lige under pladekanten
            ctx.addPath(Drawing.circle(c, g.recordRadius + 0.6)); ctx.setFillColor(Drawing.gray(0.05)); ctx.fillPath()
        }
    }

    static func platterMargin(_ g: TurntableGeometry) -> CGFloat { g.h * 0.09 }

    /// Børstet metalkant med "konisk" lys (fast lys – derfor må tallerkenen ligge stille).
    static func rimTexture(_ g: TurntableGeometry, side: CGFloat, scale: CGFloat) -> CGImage? {
        let stops: [(Float, Float)] = [(0.00, 0.62), (0.10, 0.95), (0.22, 0.70), (0.36, 0.50), (0.50, 0.82), (0.60, 0.98),
                                       (0.72, 0.62), (0.86, 0.46), (1.00, 0.62)]
        func metal(_ u: Float) -> Float {
            for i in 1..<stops.count where u <= stops[i].0 {
                let (a, b) = (stops[i - 1], stops[i])
                return a.1 + (b.1 - a.1) * (u - a.0) / (b.0 - a.0)
            }
            return stops.last!.1
        }
        let c = Float(side / 2), Rp = Float(g.platterRadius), sc = Float(scale)
        let n = ValueNoise(seed: 41)
        return Drawing.pixels(size: CGSize(width: side, height: side), scale: scale) { x, y in
            let dx = x - c, dy = y - c
            let r = (dx * dx + dy * dy).squareRoot()
            let cov = min(max((Rp - r) * sc + 0.5, 0), 1)
            if cov <= 0 { return .zero }
            var u = (atan2(dy, dx) + .pi / 4) / (2 * .pi)
            u -= u.rounded(.down)
            var l = metal(u) + (n.value(r * sc * 1.3, 2) - 0.5) * 0.06
            l *= cov
            return SIMD4(l, l, l, cov)
        }
    }

    /// Lysrefleksen: fast lag oven på den drejende plade. To modsatte lyse "vinger" i rillerne + spindel.
    static func sheen(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let R = Float(g.recordRadius)
        let side = CGFloat(R * 2)
        let fi = Float(g.grooveInnerRadius) / R, fo = Float(g.grooveOuterRadius) / R, fl = Float(g.labelRadius) / R
        let sc = Float(scale)
        let lightAngle: Float = -2.25        // øverst til venstre
        func angDist(_ a: Float, _ b: Float) -> Float {
            var d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            return d
        }
        func wing(_ d: Float, _ s: Float) -> Float { exp(-(d * d) / (s * s)) }
        guard let base = Drawing.pixels(size: CGSize(width: side, height: side), scale: scale, { x, y in
            let dx = x - R, dy = y - R
            let r = (dx * dx + dy * dy).squareRoot()
            let cov = min(max((R - r) * sc + 0.5, 0), 1)
            if cov <= 0 { return .zero }
            let f = r / R
            let a = atan2(dy, dx)
            let d1 = angDist(a, lightAngle), d2 = angDist(a, lightAngle + .pi)
            // smallere kerne der bliver lidt bredere udad (som på en rigtig plade)
            let core: Float = 0.10 + 0.08 * f
            var i = 0.34 * wing(d1, core) + 0.11 * wing(d1, 0.55) + 0.22 * wing(d2, core) + 0.07 * wing(d2, 0.55)
            let zone: Float
            if f < fl { zone = 0.10 }
            else if f < fi { zone = 0.45 }
            else if f <= fo { zone = 0.70 + 0.30 * sin(.pi * (f - fi) / (fo - fi)) }
            else { zone = 0.55 }
            i *= zone
            // svag generel glans fra lyskilden
            i += 0.03 * max(0, -(dx + dy) / (R * 1.4142)) * (f > fl ? 1 : 0.3)
            let al = min(1, i) * cov
            return SIMD4(al, al, al, al)
        }) else { return nil }
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            PlinthRenderer.drawUpright(ctx, base, in: CGRect(x: 0, y: 0, width: side, height: side))
            // Spindel (fast; den er rund, så det er lige meget at den ikke drejer)
            let c = CGPoint(x: side / 2, y: side / 2), sr = g.spindleRadius
            Drawing.fill(ctx, Drawing.circle(c, sr),
                         Drawing.gradient([(0, Drawing.gray(1.0)), (0.5, Drawing.gray(0.72)), (1, Drawing.gray(0.35))]),
                         from: CGPoint(x: c.x - sr, y: c.y - sr), to: CGPoint(x: c.x + sr, y: c.y + sr))
            ctx.addPath(Drawing.circle(c, sr)); ctx.setStrokeColor(Drawing.gray(0, 0.4)); ctx.setLineWidth(0.4); ctx.strokePath()
        }
    }

    /// Glød til den lille LED (lægges ovenpå fatningen og tones ind/ud).
    static func ledGlow(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let lr = g.ledRadius, side = lr * 8
        let c = CGPoint(x: side / 2, y: side / 2)
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            let glow = Drawing.gradient([(0, Drawing.color(1, 0.30, 0.16, 0.55)), (0.25, Drawing.color(1, 0.25, 0.12, 0.22)), (1, Drawing.color(1, 0.2, 0.1, 0))])
            ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2, options: [])
            let core = Drawing.gradient([(0, Drawing.color(1, 0.85, 0.7)), (0.45, Drawing.color(1, 0.32, 0.16)), (1, Drawing.color(0.75, 0.10, 0.05))])
            ctx.saveGState()
            ctx.addPath(Drawing.circle(c, lr)); ctx.clip()
            ctx.drawRadialGradient(core, startCenter: CGPoint(x: c.x - lr * 0.3, y: c.y - lr * 0.3), startRadius: 0,
                                   endCenter: c, endRadius: lr, options: [])
            ctx.restoreGState()
        }
    }
}

// MARK: - Etiket

enum LabelRenderer {
    static func image(_ content: LabelContent, _ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let lr = g.labelRadius, side = lr * 2
        let c = CGPoint(x: lr, y: lr)
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            ctx.saveGState()
            ctx.addPath(Drawing.circle(c, lr)); ctx.clip()
            switch content {
            case .cover(_, let image, let title, let artist):
                if let cg = Drawing.cgImage(image), cg.width > 0, cg.height > 0 {
                    let w = CGFloat(cg.width), h = CGFloat(cg.height)
                    let k = side / min(w, h)
                    let rect = CGRect(x: c.x - w * k / 2, y: c.y - h * k / 2, width: w * k, height: h * k)
                    PlinthRenderer.drawUpright(ctx, cg, in: rect)
                } else {
                    // QA M5: coveret kan ikke læses → tekst-etiket i stedet for en sort etiket.
                    paper(ctx, c, lr, tint: 1)
                    drawLabelText(ctx, title: title, artist: artist, c: c, lr: lr)
                }
            case .text(_, let title, let artist):
                paper(ctx, c, lr, tint: 1)
                drawLabelText(ctx, title: title, artist: artist, c: c, lr: lr)
            case .blank:
                paper(ctx, c, lr, tint: 0.97)
            }
            // presset ring og let skygge ind mod kanten (papir/tryk)
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(0, 0)), (0.82, Drawing.gray(0, 0)), (1, Drawing.gray(0, 0.28))]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: lr, options: [])
            if !g.flat {
                ctx.addPath(Drawing.circle(c, lr * 0.93)); ctx.setStrokeColor(Drawing.gray(0, 0.12)); ctx.setLineWidth(max(0.3, lr * 0.012)); ctx.strokePath()
            }
            ctx.restoreGState()
            // spindelhul (flad: kun en diskret prik, som på referencen)
            if g.flat {
                ctx.addPath(Drawing.circle(c, g.h * 0.006)); ctx.setFillColor(Drawing.gray(0, 0.35)); ctx.fillPath()
                return
            }
            let hr = g.holeRadius
            Drawing.fill(ctx, Drawing.circle(c, hr), Drawing.gradient([(0, Drawing.gray(0.02)), (1, Drawing.gray(0.18))]),
                         from: CGPoint(x: c.x, y: c.y - hr), to: CGPoint(x: c.x, y: c.y + hr))
        }
    }

    static func paper(_ ctx: CGContext, _ c: CGPoint, _ lr: CGFloat, tint: CGFloat) {
        ctx.addPath(Drawing.circle(c, lr))
        ctx.setFillColor(Drawing.color(0.94 * tint, 0.90 * tint, 0.81 * tint)); ctx.fillPath()
        ctx.addPath(Drawing.circle(c, lr * 0.80)); ctx.setStrokeColor(Drawing.color(0.55, 0.40, 0.28, 0.35))
        ctx.setLineWidth(max(0.3, lr * 0.015)); ctx.strokePath()
        ctx.addPath(Drawing.circle(c, lr * 0.28)); ctx.setStrokeColor(Drawing.color(0.55, 0.40, 0.28, 0.25))
        ctx.setLineWidth(max(0.3, lr * 0.012)); ctx.strokePath()
    }

    static func drawLabelText(_ ctx: CGContext, title: String, artist: String, c: CGPoint, lr: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        para.lineHeightMultiple = 0.9
        let ink = NSColor(srgbRed: 0.32, green: 0.20, blue: 0.13, alpha: 1)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: lr * 0.19, weight: .semibold), .foregroundColor: ink, .paragraphStyle: para,
        ]
        let artistAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: lr * 0.15, weight: .regular), .foregroundColor: ink.withAlphaComponent(0.8),
            .paragraphStyle: para,
        ]
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let tw = lr * 1.35
        let titleRect = CGRect(x: c.x - tw / 2, y: c.y - lr * 0.70, width: tw, height: lr * 0.60)
        // lodret centrering af titlen over hullet
        let measured = (title as NSString).boundingRect(with: titleRect.size, options: opts, attributes: titleAttr)
        let th = min(measured.height, titleRect.height)
        (title as NSString).draw(with: CGRect(x: titleRect.minX, y: c.y - lr * 0.10 - th, width: tw, height: th),
                                 options: opts, attributes: titleAttr)
        let aw = lr * 1.25
        (artist as NSString).draw(with: CGRect(x: c.x - aw / 2, y: c.y + lr * 0.12, width: aw, height: lr * 0.2),
                                  options: opts, attributes: artistAttr)
        NSGraphicsContext.restoreGraphicsState()
    }
}


// MARK: - Flad stil (referencebilledet)

/// Den lyse, gennemskinnelige plade: kroppens farve gjort lys, fine bløde riller, glat kant og zone ved etiketten,
/// tynd lys yderkant. Blød, lav skygge under pladen; svag fast refleks ovenpå.
enum FlatRecordRenderer {
    static func record(_ g: TurntableGeometry, _ p: FlatPalette, scale: CGFloat) -> CGImage? {
        let R = Float(g.recordRadius)
        let side = CGFloat(R * 2)
        let fi = Float(g.grooveInnerRadius) / R, fo = Float(g.grooveOuterRadius) / R, fl = Float(g.labelRadius) / R
        let sc = Float(scale)
        let base = p.record, alpha = p.recordAlpha
        let n = ValueNoise(seed: 61), n2 = ValueNoise(seed: 83), n3 = ValueNoise(seed: 7)
        let bands: [Float] = [0.66, 0.80, 0.91].map { fi + ($0 - 0.55) / 0.42 * (fo - fi) }
        return Drawing.pixels(size: CGSize(width: side, height: side), scale: scale) { x, y in
            let dx = x - R, dy = y - R
            let r = (dx * dx + dy * dy).squareRoot()
            let cov = min(max((R - r) * sc + 0.5, 0), 1)
            if cov <= 0 { return .zero }
            let f = r / R
            var l: Float = 1
            if f > fo {
                // glat yderkant, lysere, med en tynd lys kant helt yderst og en svag mørk kant lige inden for
                l = 1.045 + 0.07 * smoothstep(0.986, 0.998, f) - 0.03 * max(0, 1 - abs(f - fo) * R / 0.9)
            } else if f >= fi {
                let fine = n.value(r * sc * 0.7, 2.3) - 0.5                 // fine riller
                let soft = n2.value(r * 0.07, 5.1) - 0.5                    // bløde bånd
                l = 0.985 + 0.02 * fine + 0.04 * soft
                for b in bands {
                    // bløde trin (som referencens tydelige ringe): lys linje med en svag skygge indenfor
                    let d = (f - b) * R
                    l += 0.06 * max(0, 1 - abs(d) / 1.0) - 0.035 * max(0, 1 - abs(d + 1.6) / 1.4)
                }
                l -= 0.03 * (1 - smoothstep(fi, fi + 0.02, f))
            } else if f > fl {
                // glat zone ved etiketten, lidt lysere, med en tydelig ring ved overgangen til rillerne
                l = 1.02
                let edge = (f - fi) * R
                l += 0.06 * max(0, 1 - abs(edge) / 0.9) - 0.04 * max(0, 1 - abs(edge + 1.5) / 1.2)
            }
            l *= 1 + (n3.value(x * 1.7, y * 1.7) - 0.5) * 0.012           // mat kornethed
            let c = base * l
            let a = alpha * cov
            return SIMD4(min(c.x, 1) * a, min(c.y, 1) * a, min(c.z, 1) * a, a)
        }
    }

    /// Kun skyggen under pladen (blød og lav). Selve pladen er gennemskinnelig, så skyggen fjernes under den.
    static func shadow(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let m = RecordRenderer.platterMargin(g), R = g.recordRadius
        let side = (g.platterRadius + m) * 2
        let c = CGPoint(x: side / 2, y: side / 2)
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            ctx.saveGState()
            // skygge alene: figuren tegnes langt udenfor, skyggen forskydes tilbage
            let far: CGFloat = 4000
            ctx.setShadow(offset: CGSize(width: far * scale, height: -g.h * 0.014 * scale), blur: g.h * 0.06 * scale,
                          color: Drawing.gray(0, 0.26))
            ctx.addPath(Drawing.circle(CGPoint(x: c.x - far, y: c.y), R)); ctx.setFillColor(Drawing.gray(0)); ctx.fillPath()
            ctx.restoreGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(Drawing.circle(c, R * 0.985)); ctx.fillPath()
        }
    }

    /// Fast, blød refleks: to brede, svage lyse "vinger" og en svag glans; ingen spindel.
    static func sheen(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let R = Float(g.recordRadius)
        let side = CGFloat(R * 2)
        let fl = Float(g.labelRadius) / R
        let sc = Float(scale)
        let light: Float = -2.2
        func angDist(_ a: Float, _ b: Float) -> Float {
            var d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            return d
        }
        return Drawing.pixels(size: CGSize(width: side, height: side), scale: scale) { x, y in
            let dx = x - R, dy = y - R
            let r = (dx * dx + dy * dy).squareRoot()
            let cov = min(max((R - r) * sc + 0.5, 0), 1)
            if cov <= 0 { return .zero }
            let f = r / R
            let a = atan2(dy, dx)
            let d1 = angDist(a, light), d2 = angDist(a, light + .pi)
            var i = 0.13 * exp(-(d1 * d1) / 0.10) + 0.16 * exp(-(d2 * d2) / 0.06) * smoothstep(0.55, 0.95, f)
            i += 0.035 * max(0, -(dx + dy) / (R * 1.4142))
            i *= f < fl ? 0.25 : 1
            let al = min(1, i) * cov
            return SIMD4(al, al, al * 0.98, al)
        }
    }
}
