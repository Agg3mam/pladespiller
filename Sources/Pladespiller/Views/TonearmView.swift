import CoreGraphics

/// Tegner pickuparmen i armens lokale koordinater (omdrejningspunkt = (0,0), armen langs +x, +y mod pladen).
/// Det samme billede bruges sort og sløret som skygge.
///
/// Armen er bygget af rigtige dele (designsystemet "Pladespiller" ▸ Tonearm): kardanleje med åg, rund modvægt med
/// rifling og nåletryksskive, rundt rør, muffe, vinklet pickuphoved med fingerløft, sort pickup med rød front og nål.
/// - Træ, Aluminium, Sort, Auto: realistisk, med børstet aluminium og fint korn i de sorte dele.
/// - Flad: samme former i én flad farve uden struktur – hvid i lys tilstand, sort i mørk (`style.flatArmDark`).
enum ArmRenderer {
    enum Finish {
        case realistic
        case flat(dark: Bool)
        case silhouette
    }

    /// Billedets udstrækning i lokale koordinater.
    static func bounds(_ g: TurntableGeometry) -> CGRect {
        let h = g.h
        let minX = g.counterweightEnd - h * 0.03
        let maxX = g.tubeLength + g.headshellLength + h * 0.035
        return CGRect(x: minX, y: -h * 0.075, width: maxX - minX, height: h * 0.075 + h * 0.10)
    }

    /// Omdrejningspunktets placering i billedet (y nedad, 0...1).
    static func pivotUnit(_ g: TurntableGeometry) -> CGPoint {
        let b = bounds(g)
        return CGPoint(x: -b.minX / b.width, y: -b.minY / b.height)
    }

    static func image(_ g: TurntableGeometry, scale: CGFloat, finish: Finish) -> CGImage? {
        let b = bounds(g)
        let tex = finish.isRealistic ? Textures(size: b.size, scale: scale) : nil
        return Drawing.image(size: b.size, scale: scale) { ctx in
            ctx.translateBy(x: -b.minX, y: -b.minY)
            draw(ctx, g, finish: finish, textures: tex, origin: b.origin)
        }
    }

    /// Strukturer til den realistiske arm, tegnet én gang pr. billede i armbilledets størrelse.
    struct Textures {
        let brushed: CGImage?     // fine striber på langs (rør, pickuphoved, åg)
        let lathe: CGImage?       // drejespor på tværs (modvægt)
        let grain: CGImage?       // fint korn (sort anodiseret metal og plast)
        init(size: CGSize, scale: CGFloat) {
            brushed = Drawing.noise(size: size, scale: scale, fx: 0.012, fy: 0.85, seed: 5)
            lathe = Drawing.noise(size: size, scale: scale, fx: 0.85, fy: 0.02, seed: 6)
            grain = Drawing.noise(size: size, scale: scale, fx: 0.7, fy: 0.7, seed: 8, contrast: 1.6)
        }
    }

    // MARK: Farver (fra designsystemets tokens)

    private static let aluHi = Drawing.color(0.984, 0.984, 0.980)
    private static let aluMid = Drawing.color(0.776, 0.788, 0.804)
    private static let aluLow = Drawing.color(0.553, 0.569, 0.592)
    private static let aluShadow = Drawing.color(0.361, 0.376, 0.400)
    private static let bearingBlack = Drawing.color(0.114, 0.118, 0.129)
    private static let bearingRing = Drawing.color(0.271, 0.278, 0.298)
    private static let cartridgeBody = Drawing.color(0.094, 0.094, 0.102)
    private static let cartridgeAccent = Drawing.color(0.831, 0.251, 0.184)
    private static let cantilever = Drawing.color(0.788, 0.659, 0.361)

    static func flatColors(dark: Bool) -> (fill: CGColor, edge: CGColor) {
        dark ? (Drawing.color(0.122, 0.125, 0.137), Drawing.color(0.227, 0.231, 0.251))
             : (Drawing.color(0.965, 0.965, 0.953), Drawing.color(0.839, 0.839, 0.816))
    }

    // MARK: Tegning

    static func draw(_ ctx: CGContext, _ g: TurntableGeometry, finish: Finish, textures tex: Textures?, origin: CGPoint) {
        let h = g.h, w = g.tubeWidth
        let texRect = CGRect(origin: origin, size: bounds(g).size)
        let sil: Bool = if case .silhouette = finish { true } else { false }
        let flat: (fill: CGColor, edge: CGColor)? = if case .flat(let dark) = finish { flatColors(dark: dark) } else { nil }
        let black = Drawing.gray(0)

        /// Fyld en del: sort (skygge), flad farve med tynd kant (Flad) eller gradient + struktur (realistisk).
        func part(_ path: CGPath, _ gradient: @autoclosure () -> CGGradient, across a: CGPoint, _ b: CGPoint,
                  texture: CGImage? = nil, alpha: CGFloat = 0.5) {
            if sil { ctx.addPath(path); ctx.setFillColor(black); ctx.fillPath(); return }
            if let flat {
                ctx.addPath(path); ctx.setFillColor(flat.fill); ctx.fillPath()
                ctx.addPath(path); ctx.setStrokeColor(flat.edge); ctx.setLineWidth(max(0.5, h * 0.0018)); ctx.strokePath()
                return
            }
            Drawing.fill(ctx, path, gradient(), from: a, to: b)
            Drawing.texture(ctx, path, texture, in: texRect, alpha: alpha)
        }
        func solid(_ path: CGPath, _ color: CGColor, texture: CGImage? = nil, alpha: CGFloat = 0.5) {
            part(path, Drawing.gradient([(0, color), (1, color)]), across: .zero, .zero, texture: texture, alpha: alpha)
        }
        let cylinder = Drawing.gradient([(0, aluLow), (0.30, aluHi), (0.62, aluMid), (1, aluShadow)])
        let weight = Drawing.gradient([(0, aluShadow), (0.28, aluHi), (0.55, aluMid), (1, aluShadow)])
        let real = flat == nil && !sil

        // Bagerste stump og modvægt (rund cylinder, riflet bagtil, nåletryksskive fortil)
        let stub = CGPath(rect: CGRect(x: g.counterweightEnd + h * 0.005, y: -w * 0.42, width: -g.counterweightEnd - h * 0.005, height: w * 0.84),
                          transform: nil)
        part(stub, cylinder, across: CGPoint(x: 0, y: -w * 0.42), CGPoint(x: 0, y: w * 0.42), texture: tex?.brushed, alpha: 0.6)
        let cwR = g.counterweightRadius
        let cw = CGRect(x: g.counterweightEnd, y: -cwR, width: g.counterweightStart - g.counterweightEnd, height: cwR * 2)
        let cwPath = CGPath(roundedRect: cw, cornerWidth: cwR * 0.22, cornerHeight: cwR * 0.22, transform: nil)
        part(cwPath, weight, across: CGPoint(x: 0, y: -cwR), CGPoint(x: 0, y: cwR), texture: tex?.lathe, alpha: 0.55)
        if real {
            ctx.setStrokeColor(aluShadow.copy(alpha: 0.6)!); ctx.setLineWidth(max(0.3, h * 0.0012))
            var x = cw.minX + h * 0.006
            while x < cw.minX + cw.width * 0.42 {
                ctx.move(to: CGPoint(x: x, y: -cwR * 0.94)); ctx.addLine(to: CGPoint(x: x, y: cwR * 0.94))
                x += h * 0.0038
            }
            ctx.strokePath()
            ctx.addPath(cwPath); ctx.setStrokeColor(Drawing.gray(0, 0.3)); ctx.setLineWidth(0.5); ctx.strokePath()
        }
        let dw = h * 0.016
        let dial = CGPath(roundedRect: CGRect(x: g.counterweightStart - dw, y: -cwR * 1.05, width: dw, height: cwR * 2.1),
                          cornerWidth: dw * 0.25, cornerHeight: dw * 0.25, transform: nil)
        solid(dial, bearingBlack, texture: tex?.grain, alpha: 0.35)
        if real {
            ctx.setLineWidth(max(0.3, h * 0.0012))
            for i in -4...4 {
                let y = cwR * CGFloat(i) * 0.2
                ctx.move(to: CGPoint(x: g.counterweightStart - dw * 0.8, y: y))
                ctx.addLine(to: CGPoint(x: g.counterweightStart - dw * (i == 0 ? 0.15 : 0.45), y: y))
                ctx.setStrokeColor(i == 0 ? cartridgeAccent : aluHi)
                ctx.strokePath()
            }
        }

        // Armrøret: rundt aluminium med et lyst stræk langs toppen
        let tube = CGPath(roundedRect: CGRect(x: -h * 0.01, y: -w / 2, width: g.tubeLength + h * 0.01, height: w),
                          cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        part(tube, cylinder, across: CGPoint(x: 0, y: -w / 2), CGPoint(x: 0, y: w / 2), texture: tex?.brushed, alpha: 0.6)
        if real {
            ctx.move(to: CGPoint(x: h * 0.03, y: -w * 0.16)); ctx.addLine(to: CGPoint(x: g.tubeLength - h * 0.03, y: -w * 0.16))
            ctx.setStrokeColor(Drawing.gray(1, 0.6)); ctx.setLineWidth(w * 0.16); ctx.setLineCap(.round); ctx.strokePath()
        }
        // Muffe mellem rør og pickuphoved
        let collar = CGPath(roundedRect: CGRect(x: g.tubeLength - h * 0.024, y: -w * 0.92, width: h * 0.026, height: w * 1.84),
                            cornerWidth: w * 0.35, cornerHeight: w * 0.35, transform: nil)
        solid(collar, bearingBlack, texture: tex?.grain, alpha: 0.35)

        // Pickuphoved (vinklet), fingerløft, pickup med skruer, nålebøjlen stikker lige frem
        ctx.saveGState()
        ctx.translateBy(x: g.tubeLength, y: 0)
        ctx.rotate(by: g.headshellAngle)
        let hl = g.headshellLength, hw = g.headshellWidth
        let lift = CGMutablePath()
        lift.move(to: CGPoint(x: hl * 0.52, y: -hw * 0.46))
        lift.addQuadCurve(to: CGPoint(x: hl * 0.8, y: -hw * 1.32), control: CGPoint(x: hl * 0.56, y: -hw * 1.15))
        ctx.addPath(lift)
        ctx.setStrokeColor(sil ? black : flat?.edge ?? aluMid)
        ctx.setLineWidth(max(0.9, h * 0.0075)); ctx.setLineCap(.round); ctx.strokePath()
        let plate = CGMutablePath()
        plate.move(to: CGPoint(x: -h * 0.004, y: -w * 0.85))
        plate.addLine(to: CGPoint(x: hl * 0.28, y: -hw / 2))
        plate.addLine(to: CGPoint(x: hl, y: -hw / 2))
        plate.addQuadCurve(to: CGPoint(x: hl, y: hw / 2), control: CGPoint(x: hl * 1.04, y: 0))
        plate.addLine(to: CGPoint(x: hl * 0.28, y: hw / 2))
        plate.addLine(to: CGPoint(x: -h * 0.004, y: w * 0.85))
        plate.closeSubpath()
        part(plate, Drawing.gradient([(0, aluMid), (0.4, aluHi), (1, aluLow)]), across: CGPoint(x: 0, y: -hw / 2), CGPoint(x: 0, y: hw / 2),
             texture: tex?.brushed, alpha: 0.5)
        if real {
            ctx.addPath(plate); ctx.setStrokeColor(Drawing.gray(0, 0.3)); ctx.setLineWidth(0.45); ctx.strokePath()
            let cart = CGRect(x: hl * 0.40, y: -hw * 0.34, width: hl * 0.56, height: hw * 0.68)
            solid(CGPath(roundedRect: cart, cornerWidth: hw * 0.08, cornerHeight: hw * 0.08, transform: nil), cartridgeBody,
                  texture: tex?.grain, alpha: 0.35)
            ctx.addPath(CGPath(roundedRect: CGRect(x: cart.minX, y: cart.minY, width: cart.width, height: cart.height * 0.28),
                               cornerWidth: hw * 0.08, cornerHeight: hw * 0.08, transform: nil))
            ctx.setFillColor(Drawing.gray(1, 0.08)); ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: CGRect(x: hl * 0.86, y: cart.minY, width: hl * 0.10, height: cart.height),
                               cornerWidth: hw * 0.06, cornerHeight: hw * 0.06, transform: nil))
            ctx.setFillColor(cartridgeAccent); ctx.fillPath()
            for y in [-hw * 0.17, hw * 0.17] {
                ctx.addPath(Drawing.circle(CGPoint(x: hl * 0.55, y: y), max(0.45, hw * 0.075))); ctx.setFillColor(aluHi); ctx.fillPath()
            }
            ctx.move(to: CGPoint(x: hl * 0.93, y: 0)); ctx.addLine(to: CGPoint(x: hl * 1.02, y: 0))
            ctx.setStrokeColor(cantilever); ctx.setLineWidth(max(0.5, h * 0.0028)); ctx.setLineCap(.round); ctx.strokePath()
        } else if let flat {
            // Flad: kun pickuppens omrids, så formen kan ses
            ctx.addPath(CGPath(roundedRect: CGRect(x: hl * 0.40, y: -hw * 0.34, width: hl * 0.56, height: hw * 0.68),
                               cornerWidth: hw * 0.08, cornerHeight: hw * 0.08, transform: nil))
            ctx.setStrokeColor(flat.edge); ctx.setLineWidth(max(0.5, h * 0.0018)); ctx.strokePath()
        }
        ctx.restoreGState()

        // Kardanleje: åg med to tapper på tværs, sort hus, aluminiumshætte
        let b = g.bearingRadius
        let yoke = CGPath(roundedRect: CGRect(x: -b * 0.42, y: -b - h * 0.012, width: b * 0.84, height: 2 * b + h * 0.024),
                          cornerWidth: b * 0.2, cornerHeight: b * 0.2, transform: nil)
        part(yoke, cylinder, across: CGPoint(x: -b * 0.42, y: 0), CGPoint(x: b * 0.42, y: 0), texture: tex?.brushed, alpha: 0.5)
        let housing = Drawing.circle(.zero, b)
        part(housing, Drawing.gradient([(0, bearingRing), (1, bearingBlack)]), across: CGPoint(x: -b * 0.6, y: -b * 0.7), CGPoint(x: b * 0.5, y: b * 0.6),
             texture: tex?.grain, alpha: 0.35)
        let cap = Drawing.circle(.zero, b * 0.55)
        if real {
            Drawing.fill(ctx, cap, Drawing.gradient([(0, aluHi), (0.7, aluMid), (1, aluLow)]),
                         from: CGPoint(x: -b * 0.4, y: -b * 0.45), to: CGPoint(x: b * 0.5, y: b * 0.5))
            // drejet hætte: tætte, svage ringe
            ctx.setLineWidth(max(0.25, h * 0.0008))
            var r = b * 0.08
            while r < b * 0.55 {
                ctx.addPath(Drawing.circle(.zero, r)); r += max(0.6, h * 0.0024)
            }
            ctx.setStrokeColor(aluLow.copy(alpha: 0.35)!); ctx.strokePath()
            ctx.addPath(Drawing.circle(.zero, b * 0.14)); ctx.setFillColor(bearingBlack); ctx.fillPath()
            ctx.addPath(Drawing.circle(.zero, b - 0.3)); ctx.setStrokeColor(Drawing.gray(0, 0.5)); ctx.setLineWidth(0.6); ctx.strokePath()
        } else if !sil {
            part(cap, cylinder, across: .zero, .zero)
        }
    }
}

private extension ArmRenderer.Finish {
    var isRealistic: Bool { if case .realistic = self { true } else { false } }
}
