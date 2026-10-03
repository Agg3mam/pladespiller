import CoreGraphics

/// Tegner pickuparmen i armens lokale koordinater (omdrejningspunkt = (0,0), armen langs +x, +y mod pladen).
/// Det samme billede bruges sort og sløret som skygge.
enum ArmRenderer {
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

    static func image(_ g: TurntableGeometry, scale: CGFloat, silhouette: Bool) -> CGImage? {
        let b = bounds(g)
        return Drawing.image(size: b.size, scale: scale) { ctx in
            ctx.translateBy(x: -b.minX, y: -b.minY)
            draw(ctx, g, silhouette: silhouette)
        }
    }

    static func draw(_ ctx: CGContext, _ g: TurntableGeometry, silhouette s: Bool) {
        let h = g.h
        let black = Drawing.gray(0)
        func metal(_ dark: CGFloat, _ light: CGFloat) -> CGGradient {
            s ? Drawing.gradient([(0, black), (1, black)])
              : Drawing.gradient([(0, Drawing.gray(dark)), (0.30, Drawing.gray(light)), (0.55, Drawing.gray((dark + light) / 2 + 0.08)),
                                  (1, Drawing.gray(dark * 0.75))])
        }

        // Bagerste stump + modvægt
        let w = g.tubeWidth
        let stub = CGMutablePath()
        stub.move(to: CGPoint(x: g.counterweightEnd - h * 0.012, y: 0)); stub.addLine(to: .zero)
        Drawing.stroke(ctx, stub, width: w * 0.75, metal(0.30, 0.75), from: CGPoint(x: 0, y: -w), to: CGPoint(x: 0, y: w))

        let cwR = g.counterweightRadius
        let cw = CGRect(x: g.counterweightEnd, y: -cwR, width: g.counterweightStart - g.counterweightEnd, height: cwR * 2)
        let cwPath = CGPath(roundedRect: cw, cornerWidth: cwR * 0.25, cornerHeight: cwR * 0.25, transform: nil)
        Drawing.fill(ctx, cwPath, metal(0.16, 0.62), from: CGPoint(x: 0, y: -cwR), to: CGPoint(x: 0, y: cwR))
        if !s {
            // riller på modvægten
            ctx.setStrokeColor(Drawing.gray(0, 0.35)); ctx.setLineWidth(max(0.3, h * 0.0025))
            for i in 1...4 {
                let x = cw.minX + cw.width * CGFloat(i) / 5.5
                ctx.move(to: CGPoint(x: x, y: -cwR * 0.9)); ctx.addLine(to: CGPoint(x: x, y: cwR * 0.9))
            }
            ctx.strokePath()
            ctx.addPath(cwPath); ctx.setStrokeColor(Drawing.gray(0, 0.4)); ctx.setLineWidth(0.5); ctx.strokePath()
        }

        // Røret
        let tube = CGMutablePath()
        tube.move(to: .zero); tube.addLine(to: CGPoint(x: g.tubeLength, y: 0))
        Drawing.stroke(ctx, tube, width: w, metal(0.42, 0.98), from: CGPoint(x: 0, y: -w / 2), to: CGPoint(x: 0, y: w / 2))
        if !s {
            ctx.addPath(tube.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4))
            ctx.setStrokeColor(Drawing.gray(0, 0.35)); ctx.setLineWidth(0.4); ctx.strokePath()
        }

        // Pickuphoved (headshell) i en vinkel mod pladen
        ctx.saveGState()
        ctx.translateBy(x: g.tubeLength, y: 0)
        ctx.rotate(by: g.headshellAngle)
        let hl = g.headshellLength, hw = g.headshellWidth
        // fingerløft ud til siden (væk fra pladen)
        let lift = CGMutablePath()
        lift.move(to: CGPoint(x: hl * 0.40, y: -hw * 0.45))
        lift.addQuadCurve(to: CGPoint(x: hl * 0.52, y: -hw * 1.25), control: CGPoint(x: hl * 0.40, y: -hw * 1.05))
        Drawing.stroke(ctx, lift, width: max(0.7, h * 0.0075), metal(0.45, 0.95), from: CGPoint(x: 0, y: -hw), to: CGPoint(x: 0, y: 0))
        let shell = CGPath(roundedRect: CGRect(x: -h * 0.012, y: -hw / 2, width: hl + h * 0.012, height: hw),
                           cornerWidth: hw * 0.18, cornerHeight: hw * 0.18, transform: nil)
        Drawing.fill(ctx, shell, metal(0.48, 0.96), from: CGPoint(x: 0, y: -hw / 2), to: CGPoint(x: 0, y: hw / 2))
        if !s {
            ctx.addPath(shell); ctx.setStrokeColor(Drawing.gray(0, 0.4)); ctx.setLineWidth(0.45); ctx.strokePath()
            // pickup (mørk) med to skruer
            let cart = CGPath(roundedRect: CGRect(x: hl * 0.38, y: -hw * 0.34, width: hl * 0.60, height: hw * 0.68),
                              cornerWidth: hw * 0.1, cornerHeight: hw * 0.1, transform: nil)
            Drawing.fill(ctx, cart, Drawing.gradient([(0, Drawing.gray(0.22)), (1, Drawing.gray(0.04))]),
                         from: CGPoint(x: 0, y: -hw / 2), to: CGPoint(x: 0, y: hw / 2))
            let screwR = max(0.35, hw * 0.07)
            for y in [-hw * 0.2, hw * 0.2] {
                ctx.addPath(Drawing.circle(CGPoint(x: hl * 0.52, y: y), screwR)); ctx.setFillColor(Drawing.gray(0.85)); ctx.fillPath()
            }
            // samlingsmuffe
            let collar = CGRect(x: -h * 0.016, y: -w * 0.72, width: h * 0.02, height: w * 1.44)
            Drawing.fill(ctx, CGPath(roundedRect: collar, cornerWidth: w * 0.2, cornerHeight: w * 0.2, transform: nil),
                         metal(0.15, 0.55), from: CGPoint(x: 0, y: -w), to: CGPoint(x: 0, y: w))
        }
        ctx.restoreGState()

        // Lejet ved omdrejningspunktet
        let hubR = h * 0.033
        Drawing.fill(ctx, Drawing.circle(.zero, hubR),
                     s ? Drawing.gradient([(0, black), (1, black)])
                       : Drawing.gradient([(0, Drawing.gray(0.85)), (0.5, Drawing.gray(0.45)), (1, Drawing.gray(0.18))]),
                     from: CGPoint(x: -hubR, y: -hubR), to: CGPoint(x: hubR, y: hubR))
        if !s {
            ctx.addPath(Drawing.circle(.zero, hubR * 0.62)); ctx.setFillColor(Drawing.gray(0.12)); ctx.fillPath()
            ctx.addPath(Drawing.circle(.zero, hubR * 0.25)); ctx.setFillColor(Drawing.gray(0.75)); ctx.fillPath()
            ctx.addPath(Drawing.circle(.zero, hubR)); ctx.setStrokeColor(Drawing.gray(0, 0.45)); ctx.setLineWidth(0.5); ctx.strokePath()
        }
    }
}
