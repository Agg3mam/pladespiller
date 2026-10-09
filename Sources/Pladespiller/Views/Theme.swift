import AppKit
import CoreGraphics

/// Udseendet af pladespillerens krop. Nyt tema = ny `PlinthMaterial` + en case i `TurntableStyle.make`.
enum PlinthMaterial: Hashable {
    case wood(WoodSpecies)
    case aluminium
    case black
    /// Mat lakeret i en farve (tema "Auto": udledt af coveret).
    case matte(r: Float, g: Float, b: Float)
    /// Tema "Flad": ensfarvet, mat krop (referencebilledet). Farven fra `settings.flatColor`.
    case flat(r: Float, g: Float, b: Float)
}

enum WoodSpecies: String, Hashable {
    case walnut, oak
}

struct TurntableStyle: Hashable {
    var plinth: PlinthMaterial
    /// Basisplade under armen og knapper: lys eller mørk metal.
    var darkHardware: Bool
    /// Flad: armen (og dens bundplade og støtte) er sort i stedet for hvid, fordi macOS står i mørk tilstand.
    var flatArmDark = false
    /// Fuld skærm: kroppen er én ren farve (materialets farve) i stedet for et foto/mønster strakt over hele skærmen.
    var solidBody = false
    /// Armstøtte, 33/45-knapper og LED vises (kun fuld skærm; i widgetten er de for små og støder ind i teksten).
    var deckDetails = false

    /// Træsort for tema Træ. Kan ændres når brugeren har valgt (valnød eller lys eg).
    static var woodSpecies: WoodSpecies = .walnut

    var isFlat: Bool { if case .flat = plinth { true } else { false } }
    /// Farver til det flade tema (nil for de andre temaer).
    var flatPalette: FlatPalette? {
        if case let .flat(r, g, b) = plinth { FlatPalette(body: SIMD3(r, g, b)) } else { nil }
    }

    static func make(theme: TurntableTheme, artwork: NSImage?, flatColor: FlatColor = .auto,
                     customHex: String = "F2B705", flatArmDark: Bool? = nil, solidBody: Bool = false,
                     deckDetails: Bool = false) -> TurntableStyle {
        var style = makeBase(theme: theme, artwork: artwork, flatColor: flatColor, customHex: customHex, flatArmDark: flatArmDark)
        style.solidBody = solidBody && !style.isFlat
        style.deckDetails = deckDetails && !style.isFlat
        return style
    }

    private static func makeBase(theme: TurntableTheme, artwork: NSImage?, flatColor: FlatColor,
                                 customHex: String, flatArmDark: Bool?) -> TurntableStyle {
        switch theme {
        case .flat:
            TurntableStyle(plinth: flatMaterial(flatColor, customHex: customHex, artwork: artwork), darkHardware: false,
                           flatArmDark: flatArmDark ?? SystemAppearance.shared.isDark)
        case .wood: TurntableStyle(plinth: .wood(woodSpecies), darkHardware: false)
        case .aluminium: TurntableStyle(plinth: .aluminium, darkHardware: true)
        case .black: TurntableStyle(plinth: .black, darkHardware: false)
        case .auto:
            if let artwork, let material = autoMaterial(for: artwork) {
                TurntableStyle(plinth: material, darkHardware: false)
            } else {
                TurntableStyle(plinth: .black, darkHardware: false)
            }
        }
    }

    /// Auto-farven pr. cover caches (QA M4): gennemsnitsfarven regnes kun én gang pr. coverbillede.
    private static var autoCache: [ObjectIdentifier: PlinthMaterial] = [:]
    private static var autoOrder: [ObjectIdentifier] = []
    private static var autoKeepAlive: [ObjectIdentifier: NSImage] = [:]

    static func autoMaterial(for artwork: NSImage) -> PlinthMaterial? {
        let id = ObjectIdentifier(artwork)
        if let hit = autoCache[id] { return hit }
        guard let cg = Drawing.cgImage(artwork) else { return nil }
        let m = autoMaterial(from: Drawing.averageColor(cg))
        autoCache[id] = m
        autoKeepAlive[id] = artwork      // så id'et ikke genbruges af et nyt objekt mens det ligger i cachen
        autoOrder.append(id)
        while autoOrder.count > 8 {
            let old = autoOrder.removeFirst()
            autoCache[old] = nil
            autoKeepAlive[old] = nil
        }
        return m
    }

    /// Neutral farve til Flad · Auto uden cover (varm lys grå, som papir).
    static let flatNeutral = SIMD3<Float>(0.80, 0.77, 0.72)

    static func flatMaterial(_ color: FlatColor, customHex: String, artwork: NSImage?) -> PlinthMaterial {
        func q(_ v: Float) -> Float { (v * 64).rounded() / 64 }
        let c: SIMD3<Float>
        switch color {
        case .auto:
            c = artwork.flatMap(flatAutoColor(for:)) ?? flatNeutral
        case .custom:
            c = FlatPalette.parseHex(customHex) ?? FlatPalette.parseHex("F2B705")!
        default:
            c = FlatPalette.parseHex(color.hex ?? "F2B705") ?? flatNeutral
        }
        return .flat(r: q(c.x), g: q(c.y), b: q(c.z))
    }

    /// Flad · Auto: coverets FREMHERSKENDE farve (ikke gennemsnittet, der bliver mudret), gjort klar og mat.
    private static var flatAutoCache: [ObjectIdentifier: SIMD3<Float>] = [:]
    private static var flatAutoKeep: [ObjectIdentifier: NSImage] = [:]
    private static var flatAutoOrder: [ObjectIdentifier] = []

    static func flatAutoColor(for artwork: NSImage) -> SIMD3<Float>? {
        let id = ObjectIdentifier(artwork)
        if let hit = flatAutoCache[id] { return hit }
        guard let cg = Drawing.cgImage(artwork) else { return nil }
        let d = Drawing.dominantColor(cg)
        let ns = NSColor(srgbRed: CGFloat(d.x), green: CGFloat(d.y), blue: CGFloat(d.z), alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        let out: SIMD3<Float>
        if sat < 0.12 {
            if bri > 0.5 {
                out = flatNeutral                                          // lyst gråt cover: neutral, som papir
            } else {
                // Mørkt/gråt cover: ingen mudret grå. Lån coverets farvetone fra gennemsnittet, hvis der er en;
                // ellers den faste gule farve (referencen).
                let avg = Drawing.averageColor(cg)
                let an = NSColor(srgbRed: CGFloat(avg.x), green: CGFloat(avg.y), blue: CGFloat(avg.z), alpha: 1)
                var ah: CGFloat = 0, asat: CGFloat = 0, abri: CGFloat = 0, aa: CGFloat = 0
                an.getHue(&ah, saturation: &asat, brightness: &abri, alpha: &aa)
                if asat > 0.15, let o = NSColor(hue: ah, saturation: min(max(asat, 0.45), 0.8), brightness: 0.62, alpha: 1)
                    .usingColorSpace(.sRGB) {
                    out = SIMD3(Float(o.redComponent), Float(o.greenComponent), Float(o.blueComponent))
                } else {
                    out = FlatPalette.parseHex("F2B705")!
                }
            }
        } else {
            let o = NSColor(hue: hue, saturation: min(max(sat, 0.38), 0.82), brightness: min(max(bri, 0.52), 0.92), alpha: 1)
                .usingColorSpace(.sRGB) ?? ns
            out = SIMD3(Float(o.redComponent), Float(o.greenComponent), Float(o.blueComponent))
        }
        flatAutoCache[id] = out
        flatAutoKeep[id] = artwork
        flatAutoOrder.append(id)
        while flatAutoOrder.count > 8 {
            let old = flatAutoOrder.removeFirst()
            flatAutoCache[old] = nil
            flatAutoKeep[old] = nil
        }
        return out
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
        if let palette = style.flatPalette { return flatImage(g, style: style, palette: palette, scale: scale) }
        if style.solidBody { return solidImage(g, style: style, scale: scale) }
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

    /// Fuld skærm: én ren farve (materialets egen farve) med kun et meget blødt lys fra oven, plus de faste detaljer.
    static func solidImage(_ g: TurntableGeometry, style: TurntableStyle, scale: CGFloat) -> CGImage? {
        let c = solidColor(style.plinth)
        return Drawing.image(size: g.size, scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: g.size)
            ctx.setFillColor(Drawing.color(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
            ctx.fill(rect)
            Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                         Drawing.gradient([(0, Drawing.gray(1, 0.04)), (0.55, Drawing.gray(1, 0)), (1, Drawing.gray(0, 0.06))]),
                         from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
            details(ctx, g, style: style, scale: scale)
        }
    }

    /// Materialets farve: træ = gennemsnittet af træfotoet (dyb valnød), aluminium lys grå, sort næsten sort.
    static func solidColor(_ m: PlinthMaterial) -> SIMD3<Float> {
        switch m {
        case .wood:
            if let wood = WoodTexture.image { return Drawing.averageColor(wood) * 0.92 }
            return SIMD3(0.25, 0.13, 0.07)
        case .aluminium: return SIMD3(0.76, 0.77, 0.78)
        case .black: return SIMD3(0.075, 0.075, 0.08)
        case let .matte(r, g, b), let .flat(r, g, b): return SIMD3(r, g, b)
        }
    }

    /// Flad krop (referencebilledet): ensfarvet og mat med svag kornethed, næsten intet lys, ingen kant;
    /// kun en svag rund fordybning bag armens leje og en lille armstøtte.
    static func flatImage(_ g: TurntableGeometry, style: TurntableStyle, palette p: FlatPalette, scale: CGFloat) -> CGImage? {
        let texture = materialTexture(style.plinth, size: g.size, h: g.h, scale: scale)
        func col(_ c: SIMD3<Float>, _ a: CGFloat = 1) -> CGColor { Drawing.color(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), a) }
        return Drawing.image(size: g.size, scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: g.size)
            let shape = CGPath(roundedRect: rect, cornerWidth: g.cornerRadius, cornerHeight: g.cornerRadius, transform: nil)
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            if let texture { drawUpright(ctx, texture, in: rect) }
            // meget blødt lys fra oven
            Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                         Drawing.gradient([(0, Drawing.gray(1, 0.05)), (0.55, Drawing.gray(1, 0)), (1, Drawing.gray(0, 0.05))]),
                         from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))

            ctx.restoreGState()
            flatArmBase(ctx, g, dark: style.flatArmDark, scale: scale)
        }
    }

    /// Flad: rund bundplade under lejet (med en lille antiskating-knap) og armstøtten, i armens flade farve med tynd kant.
    static func flatArmBase(_ ctx: CGContext, _ g: TurntableGeometry, dark: Bool, scale: CGFloat) {
        let h = g.h, colors = ArmRenderer.flatColors(dark: dark)
        func part(_ c: CGPoint, _ r: CGFloat, shadow: Bool) {
            if shadow {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: h * 0.004 * scale, height: -h * 0.008 * scale), blur: h * 0.018 * scale,
                              color: Drawing.gray(0, 0.22))
                ctx.addPath(Drawing.circle(c, r)); ctx.setFillColor(colors.fill); ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.addPath(Drawing.circle(c, r)); ctx.setFillColor(colors.fill); ctx.fillPath()
            ctx.addPath(Drawing.circle(c, r - 0.3)); ctx.setStrokeColor(colors.edge); ctx.setLineWidth(max(0.5, h * 0.0018)); ctx.strokePath()
        }
        let p = g.pivot, br = g.basePlateRadius
        part(p, br, shadow: true)
        part(CGPoint(x: p.x + br * 0.7 * cos(-0.75), y: p.y + br * 0.7 * sin(-0.75)), h * 0.013, shadow: false)
        part(g.world(CGPoint(x: g.armRestLocalX, y: 0), armAngle: g.restAngle), h * 0.018, shadow: true)
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
            if species == .walnut {
                if let photo = WoodTexture.fitted(size: size, scale: scale) { return photo }
                if WoodTexture.isPending {
                    // Fotoet afkodes i baggrunden: kort tid en rolig, mørk træfarve (tegnes om når fotoet er klar).
                    return Drawing.pixels(size: CGSize(width: 4, height: 4), scale: 1) { _, _ in SIMD4(0.30, 0.16, 0.09, 1) }
                }
            }
            let veneer = WoodVeneer(species: species)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let c = veneer.color(x * k, y * k)
                return SIMD4(c.x, c.y, c.z, 1)
            }
        case .aluminium:
            let n = ValueNoise(seed: 3), n2 = ValueNoise(seed: 17)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let u = x * k, v = y * k
                let brush = (n.value(u * 0.015, v * 2.6) - 0.5) * 0.06 + (n2.value(u * 0.25, v * 9) - 0.5) * 0.035
                let gch = 0.70 + brush
                return SIMD4(gch, gch, gch * 1.015, 1)
            }
        case .black:
            let n = ValueNoise(seed: 5)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let gch: Float = 0.072 + (n.value(x * k * 0.8, y * k * 0.8) - 0.5) * 0.008
                return SIMD4(gch, gch, gch * 1.04, 1)
            }
        case let .flat(r, g, b):
            // Meget svag struktur: fin, mat kornethed (som pulverlak/papir) og en næsten usynlig storskala-variation.
            let n = ValueNoise(seed: 13), n2 = ValueNoise(seed: 29)
            return Drawing.pixels(size: size, scale: scale) { x, y in
                let grain = (n.value(x * 2.1, y * 2.1) - 0.5) * 0.022
                let broad = (n2.fbm(x * 0.012, y * 0.012, octaves: 2) - 0.5) * 0.025
                let t = 1 + grain + broad
                return SIMD4(r * t, g * t, b * t, 1)
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
        case .aluminium: 0.20
        default: 0.10
        }
        Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                     Drawing.gradient([(0, Drawing.gray(1, strength)), (0.5, Drawing.gray(1, 0)), (1, Drawing.gray(0, 0.16))]),
                     from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        if case .wood = material {
            // Fotoet er en mat diffuse map: lidt mørkere og varmere, vignet mod kanterne og lak ovenpå.
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(Drawing.color(0.86, 0.80, 0.76))
            ctx.fill(rect)
            ctx.restoreGState()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(0, 0)), (0.65, Drawing.gray(0, 0.05)), (1, Drawing.gray(0, 0.32))]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: hypot(rect.width, rect.height) / 2,
                                   options: [.drawsAfterEndLocation])
            // Lak: et svagt, bredt skær på skrå.
            Drawing.fill(ctx, CGPath(rect: rect, transform: nil),
                         Drawing.gradient([(0.0, Drawing.gray(1, 0)), (0.28, Drawing.gray(1, 0.05)), (0.40, Drawing.gray(1, 0.0)),
                                           (1, Drawing.gray(1, 0))]),
                         from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
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
        // 3D-foden (SceneKit) med samme lys som armen; uden Metal den tegnede fod.
        let baseBox = Arm3D.baseRect(g)
        if let base3D = Arm3D.base(g, scale: scale) {
            drawUpright(ctx, base3D, in: baseBox.offsetBy(dx: p.x, dy: p.y))
        } else {
            // Sort, rund fod (som på en DJ-pladespiller) med en drejet sølvring om lejet og en sort antiskating-knap.
            Drawing.fill(ctx, Drawing.circle(p, br), Drawing.gradient([(0, Drawing.gray(0.24)), (0.5, Drawing.gray(0.10)), (1, Drawing.gray(0.05))]),
                         from: CGPoint(x: p.x - br, y: p.y - br), to: CGPoint(x: p.x + br, y: p.y + br))
            ctx.addPath(Drawing.circle(p, br - 0.4)); ctx.setStrokeColor(Drawing.gray(1, 0.18)); ctx.setLineWidth(0.6); ctx.strokePath()
            ctx.addPath(Drawing.circle(p, br * 0.86)); ctx.setStrokeColor(Drawing.gray(0, 0.5)); ctx.setLineWidth(max(0.4, h * 0.0016)); ctx.strokePath()
            let ringR = br * 0.62
            Drawing.fill(ctx, Drawing.circle(p, ringR), Drawing.gradient([(0, Drawing.gray(0.95)), (0.5, Drawing.gray(0.72)), (1, Drawing.gray(0.45))]),
                         from: CGPoint(x: p.x - ringR, y: p.y - ringR), to: CGPoint(x: p.x + ringR, y: p.y + ringR))
            // drejet aluminium: tætte, svage ringe og to modsatte lysvinger (lyset øverst til venstre)
            ctx.saveGState()
            ctx.addPath(Drawing.circle(p, ringR)); ctx.clip()
            var turned = ringR * 0.1
            while turned < ringR { ctx.addPath(Drawing.circle(p, turned)); turned += max(0.6, h * 0.0024) }
            ctx.setStrokeColor(Drawing.gray(0, 0.07)); ctx.setLineWidth(max(0.25, h * 0.0008)); ctx.strokePath()
            for a in [-2.2, -2.2 + CGFloat.pi] {
                let wedge = CGMutablePath()
                wedge.move(to: p)
                wedge.addArc(center: p, radius: ringR, startAngle: a - 0.22, endAngle: a + 0.22, clockwise: false)
                wedge.closeSubpath()
                ctx.addPath(wedge); ctx.setFillColor(Drawing.gray(1, 0.25)); ctx.fillPath()
            }
            ctx.restoreGState()
            ctx.addPath(Drawing.circle(p, ringR)); ctx.setStrokeColor(Drawing.gray(0, 0.45)); ctx.setLineWidth(0.6); ctx.strokePath()
            // antiskating-knap: sort, riflet kant, hvid streg
            let knob = CGPoint(x: p.x + br * 0.78 * cos(-0.35), y: p.y + br * 0.78 * sin(-0.35)), kr = br * 0.24
            ctx.saveGState()
            shadowAt(h * 0.002, h * 0.004, blur: h * 0.006, shadow)
            Drawing.fill(ctx, Drawing.circle(knob, kr), Drawing.gradient([(0, Drawing.gray(0.32)), (1, Drawing.gray(0.06))]),
                         from: CGPoint(x: knob.x - kr, y: knob.y - kr), to: CGPoint(x: knob.x + kr, y: knob.y + kr))
            ctx.restoreGState()
            for i in 0..<16 {
                let a = CGFloat(i) / 16 * 2 * .pi
                ctx.move(to: CGPoint(x: knob.x + kr * 0.82 * cos(a), y: knob.y + kr * 0.82 * sin(a)))
                ctx.addLine(to: CGPoint(x: knob.x + kr * cos(a), y: knob.y + kr * sin(a)))
            }
            ctx.setStrokeColor(Drawing.gray(1, 0.18)); ctx.setLineWidth(max(0.3, h * 0.001)); ctx.strokePath()
            ctx.move(to: knob); ctx.addLine(to: CGPoint(x: knob.x + kr * 0.7 * cos(-1.2), y: knob.y + kr * 0.7 * sin(-1.2)))
            ctx.setStrokeColor(Drawing.gray(1, 0.85)); ctx.setLineWidth(max(0.4, h * 0.0018)); ctx.strokePath()
        }

        // Armstøtte, 33/45-knapper og LED kun hvor de kan ses (fuld skærm). I widgetten er de få pixel store
        // og kolliderer med teksten i hjørnet.
        guard style.deckDetails else { return }
        let restP = g.world(CGPoint(x: g.armRestLocalX, y: 0), armAngle: g.restAngle)
        if let rest3D = Arm3D.rest(g, scale: scale) {
            drawUpright(ctx, rest3D, in: Arm3D.restRect(g).offsetBy(dx: restP.x, dy: restP.y))
        } else {
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
        }

        // 33/45-knapperne er egne lag (de kan trykkes ned) – her kun en lille fordybning i kroppen under dem.
        for c in g.speedButtons {
            ctx.addPath(Drawing.circle(c, g.speedButtonRadius * 1.12)); ctx.setFillColor(Drawing.gray(0, 0.28)); ctx.fillPath()
        }
        // LED-fatning
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


/// Valnøddefinér tegnet i kode. Modellen er en træstamme skåret på langs:
/// årringene er afstanden til en marvlinje under brættet, og snittets dybde bølger langs brættet,
/// så ringene bliver til "katedraler" og flammer. Turbulens forvrider ringene, ringafstanden varierer,
/// sentræet er mørkere, porerne er små aflange streger, figuren giver et svagt skær, og der er to små knaster.
struct WoodVeneer {
    let early: SIMD3<Float>
    let late: SIMD3<Float>
    private let n1 = ValueNoise(seed: 7), n2 = ValueNoise(seed: 31), n3 = ValueNoise(seed: 101), n4 = ValueNoise(seed: 57)
    private let knots: [(x: Float, y: Float, r: Float, s: Float)] = [(34, 118, 3.2, 9), (121, 38, 2.4, 7), (220, 96, 3.0, 8)]

    init(species: WoodSpecies) {
        switch species {
        case .walnut: early = SIMD3(0.40, 0.25, 0.15); late = SIMD3(0.16, 0.088, 0.05)
        case .oak: early = SIMD3(0.80, 0.64, 0.44); late = SIMD3(0.55, 0.38, 0.22)
        }
    }

    /// u, v i "lille-størrelse-punkter" (kroppen er ≈148 høj).
    func color(_ u: Float, _ v: Float) -> SIMD3<Float> {
        // turbulens: forvrid koordinaterne lidt før ringene beregnes
        let tu = (n2.fbm(u * 0.005, v * 0.018, octaves: 4) - 0.5)
        let tv = (n1.fbm(u * 0.004 + 9, v * 0.03, octaves: 4) - 0.5)
        let pv = v + tv * 16
        // snittets dybde i stammen bølger langs brættet → katedraler
        let z = 58 + 46 * sin(u * 0.016 + tu * 2.5) + (n1.fbm(u * 0.003, 3.3, octaves: 3) - 0.5) * 40
        let dy = pv - 232
        var r = (dy * dy + z * z).squareRoot()
        // knaster bøjer ringene
        var knotCore: Float = 0
        for k in knots {
            let dx = u - k.x, dk = v - k.y
            let d2 = dx * dx * 0.35 + dk * dk
            r += k.s * exp(-d2 / (k.r * k.r * 9))
            knotCore = max(knotCore, exp(-(dx * dx + dk * dk) / (k.r * k.r)))
        }
        // ujævn ringafstand
        let R = r + (n3.fbm(r * 0.035, 7.0, octaves: 3) - 0.5) * 26
        let ringF = R / 6.2
        let idx = ringF.rounded(.down)
        let p = ringF - idx
        let ringDark = n3.hash(Int32(idx), 9)
        let lateBand = smoothstep(0.50, 0.90, p) * (1 - smoothstep(0.95, 1.0, p))
        // porer: små aflange streger langs åren, flest i forårsveddet
        let poreN = n4.value(u * 0.32, v * 4.2)
        let pores = smoothstep(0.80, 0.94, poreN) * (1 - 0.6 * lateBand)
        let fibre = n2.value(u * 0.045, v * 3.2) - 0.5
        let tone = n1.fbm(u * 0.0028 + 20, v * 0.011, octaves: 3)
        var c = mix(early, late, lateBand * (0.50 + 0.50 * ringDark))
        c = mix(c, late * 0.7, pores * 0.5)
        c *= 1 + fibre * 0.10
        c *= 0.80 + 0.40 * tone
        // figur og skær (chatoyance): bløde lyse/mørke bånd på tværs af åren
        let fig = sin(u * 0.13 + (n4.fbm(u * 0.012, v * 0.06, octaves: 3) - 0.5) * 10 + v * 0.025)
        c *= 1 + 0.075 * fig
        // knastkerner
        c = mix(c, late * 0.55, min(1, knotCore * 1.2))
        return c
    }
}


/// 33/45-knap set ovenfra: hævet (inaktiv) eller trykket ned med lysende tal (aktiv).
enum SpeedButtonRenderer {
    static func image(_ g: TurntableGeometry, label: String, active: Bool, scale: CGFloat) -> CGImage? {
        let r = g.speedButtonRadius, side = r * 3
        let c = CGPoint(x: side / 2, y: side / 2)
        let h = g.h
        return Drawing.image(size: CGSize(width: side, height: side), scale: scale) { ctx in
            if !active {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -h * 0.005 * scale), blur: h * 0.009 * scale, color: Drawing.gray(0, 0.5))
                ctx.addPath(Drawing.circle(c, r)); ctx.setFillColor(Drawing.gray(0.4)); ctx.fillPath()
                ctx.restoreGState()
            }
            let grad = active
                ? Drawing.gradient([(0, Drawing.gray(0.48)), (1, Drawing.gray(0.70))])     // trykket ned: lys nederst
                : Drawing.gradient([(0, Drawing.gray(0.95)), (1, Drawing.gray(0.64))])     // hævet: lys øverst
            Drawing.fill(ctx, Drawing.circle(c, r), grad, from: CGPoint(x: c.x, y: c.y - r), to: CGPoint(x: c.x, y: c.y + r))
            if active {
                // indre skygge langs overkanten
                ctx.saveGState()
                ctx.addPath(Drawing.circle(c, r)); ctx.clip()
                ctx.drawRadialGradient(Drawing.gradient([(0, Drawing.gray(0, 0)), (0.7, Drawing.gray(0, 0)), (1, Drawing.gray(0, 0.35))]),
                                       startCenter: CGPoint(x: c.x, y: c.y + r * 0.15), startRadius: 0,
                                       endCenter: CGPoint(x: c.x, y: c.y + r * 0.15), endRadius: r * 1.1, options: [])
                ctx.restoreGState()
            }
            ctx.addPath(Drawing.circle(c, r - 0.25)); ctx.setStrokeColor(Drawing.gray(0, 0.35)); ctx.setLineWidth(0.5); ctx.strokePath()
            if h >= 110 {
                if active {
                    // lysende tal: en svag glød bag cifrene
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: r * 0.25 * scale, color: Drawing.color(1.0, 0.45, 0.15, 0.55))
                    PlinthRenderer.drawText(ctx, label, at: c, size: r * 0.95, color: NSColor(srgbRed: 1.0, green: 0.50, blue: 0.20, alpha: 1), weight: .heavy)
                    ctx.restoreGState()
                }
                let color = active ? NSColor(srgbRed: 1.0, green: 0.55, blue: 0.25, alpha: 1) : NSColor(white: 0.20, alpha: 1)
                PlinthRenderer.drawText(ctx, label, at: c, size: r * 0.95, color: color, weight: .bold)
            } else if active {
                ctx.addPath(Drawing.circle(c, r * 0.28)); ctx.setFillColor(Drawing.color(1.0, 0.42, 0.16)); ctx.fillPath()
            }
        }
    }
}


/// Farverne i det flade tema, udledt af kroppens farve.
struct FlatPalette: Hashable {
    let body: SIMD3<Float>

    /// Relativ luminans (sRGB, ca.).
    var luminance: Float { 0.2126 * body.x + 0.7152 * body.y + 0.0722 * body.z }
    var isLight: Bool { luminance > 0.5 }

    /// Pladen: en lys, gennemskinnelig udgave af kroppen (creme/guld på gul). På meget lyse kroppe lidt mørkere
    /// end kroppen, så den stadig kan ses; på mørke kroppe en røget, lysere tone.
    var record: SIMD3<Float> {
        let white = SIMD3<Float>(1, 0.99, 0.96)
        if luminance > 0.82 { return body * 0.90 + SIMD3(0.02, 0.015, 0) }
        if isLight { return body + (white - body) * 0.70 }
        return body + (white - body) * 0.45          // mørke kroppe: tydeligt lysere plade (ikke mudret grå)
    }
    /// Pladens gennemsigtighed (kroppens farve skinner igennem).
    var recordAlpha: Float { isLight ? 0.94 : 0.97 }

    /// Fordybningen bag armens leje: kroppen en anelse mørkere.
    var recess: SIMD3<Float> { body * 0.94 }

    /// Armens hvide dele og sølvrøret.
    var armWhite: SIMD3<Float> { SIMD3(0.97, 0.97, 0.96) }

    /// Tekst: titel (fed, mørk på lyse kroppe, lys på mørke) og kunstner (dæmpet, gennemskinnelig).
    var titleColor: NSColor {
        if isLight {
            let c = body * 0.16
            return NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 0.92)
        }
        return NSColor(white: 1, alpha: 0.95)
    }
    /// Kunstner/sangtekst: samme farve som titlen, men svagere – med den laveste dækning (fra 60 %), der stadig giver
    /// mindst 4,5:1 mod kroppen, så teksten altid kan læses.
    var secondaryColor: NSColor {
        let ink: SIMD3<Float> = isLight ? body * 0.16 : SIMD3(1, 1, 1)
        let alpha = Self.readableAlpha(ink: ink, on: body)
        return NSColor(srgbRed: CGFloat(ink.x), green: CGFloat(ink.y), blue: CGFloat(ink.z), alpha: CGFloat(alpha))
    }

    /// WCAG-kontrast (relativ luminans i lineært lys).
    static func contrast(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        func lin(_ c: Float) -> Float { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func lum(_ c: SIMD3<Float>) -> Float { 0.2126 * lin(c.x) + 0.7152 * lin(c.y) + 0.0722 * lin(c.z) }
        let la = lum(a), lb = lum(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func readableAlpha(ink: SIMD3<Float>, on body: SIMD3<Float>, minimum: Float = 4.5) -> Float {
        var a: Float = 0.6
        while a < 1 {
            if contrast(ink * a + body * (1 - a), body) >= minimum { return a }
            a += 0.02
        }
        return 1
    }

    static func parseHex(_ hex: String) -> SIMD3<Float>? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }
}
