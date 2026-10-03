import AppKit
import QuartzCore

/// Pladespilleren som et lagtræ i Core Animation.
///
/// Rækkefølge (nederst → øverst): krop · tallerken · [rotor: plade + etiketter] · refleks (fast) · LED-glød ·
/// armskygge · arm. Kun rotoren drejer; refleksen ligger fast ovenpå, så lyset ikke drejer med.
///
/// Live lægges bevægelsen ind som CA-animationer (render-serveren tegner billederne; appen laver intet pr. billede).
/// Snapshots sætter blot modelværdierne for et givet tidspunkt og kalder `render(in:)`.
final class TurntableLayer {
    let root = CALayer()
    private let plinth = CALayer()
    private let platter = CALayer()
    private let rotor = CALayer()
    private let record = CALayer()
    private let labelLayer = CALayer()
    private let previousLabelLayer = CALayer()
    private let sheen = CALayer()
    private let ledGlow = CALayer()
    private let shadowMove = CALayer()
    private let shadowRot = CALayer()
    private let shadowImage = CALayer()
    private let armRot = CALayer()
    private let armImage = CALayer()

    private(set) var geometry: TurntableGeometry?
    private(set) var style: TurntableStyle?
    private(set) var scale: CGFloat = 2

    private var allLayers: [CALayer] {
        [root, plinth, platter, rotor, record, labelLayer, previousLabelLayer, sheen, ledGlow,
         shadowMove, shadowRot, shadowImage, armRot, armImage]
    }

    init() {
        let none = NSNull()
        let noActions: [String: any CAAction] = ["contents": none, "position": none, "bounds": none, "transform": none,
                                                  "opacity": none, "hidden": none, "sublayers": none, "frame": none,
                                                  "anchorPoint": none, "contentsScale": none]
        for l in allLayers {
            l.actions = noActions
            l.contentsGravity = .resize
        }
        root.masksToBounds = false
        root.addSublayer(plinth)
        root.addSublayer(platter)
        root.addSublayer(rotor)
        rotor.addSublayer(record)
        rotor.addSublayer(labelLayer)
        rotor.addSublayer(previousLabelLayer)
        root.addSublayer(sheen)
        root.addSublayer(ledGlow)
        root.addSublayer(shadowMove)
        shadowMove.addSublayer(shadowRot)
        shadowRot.addSublayer(shadowImage)
        root.addSublayer(armRot)
        armRot.addSublayer(armImage)
    }

    /// CA på macOS har y opad; geometrien har y nedad.
    private func up(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (geometry?.size.height ?? 0) - p.y)
    }

    private func square(_ c: CGPoint, half: CGFloat) -> CGRect {
        let u = up(c)
        return CGRect(x: u.x - half, y: u.y - half, width: half * 2, height: half * 2)
    }

    /// Byg billeder og placér lagene (billigt hvis intet er ændret: billederne caches).
    func configure(_ g: TurntableGeometry, style: TurntableStyle, scale: CGFloat) {
        guard g != geometry || style != self.style || scale != self.scale else { return }
        let geometryChanged = g != geometry || scale != self.scale
        geometry = g
        self.style = style
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in allLayers { l.contentsScale = scale }

        root.bounds = CGRect(origin: .zero, size: g.size)
        root.anchorPoint = .zero
        root.position = .zero
        plinth.frame = root.bounds
        plinth.contents = TurntableImages.plinth(g, style, scale)

        if geometryChanged {
            platter.frame = square(g.center, half: g.platterRadius + RecordRenderer.platterMargin(g))
            platter.contents = TurntableImages.platter(g, scale)

            rotor.bounds = CGRect(x: 0, y: 0, width: g.recordRadius * 2, height: g.recordRadius * 2)
            rotor.position = up(g.center)
            record.frame = rotor.bounds
            record.contents = TurntableImages.record(g, scale)
            let lr = g.labelRadius
            let labelFrame = CGRect(x: g.recordRadius - lr, y: g.recordRadius - lr, width: lr * 2, height: lr * 2)
            labelLayer.frame = labelFrame
            previousLabelLayer.frame = labelFrame

            sheen.frame = square(g.center, half: g.recordRadius)
            sheen.contents = TurntableImages.sheen(g, scale)

            ledGlow.frame = square(g.ledCenter, half: g.ledRadius * 4)
            ledGlow.contents = TurntableImages.ledGlow(g, scale)

            let ab = ArmRenderer.bounds(g), pu = ArmRenderer.pivotUnit(g)
            for (rot, img, contents) in [(armRot, armImage, TurntableImages.arm(g, scale)),
                                         (shadowRot, shadowImage, TurntableImages.armShadow(g, scale))] {
                rot.bounds = .zero
                rot.position = .zero
                img.bounds = CGRect(origin: .zero, size: ab.size)
                img.anchorPoint = CGPoint(x: pu.x, y: 1 - pu.y)
                img.position = .zero
                img.contents = contents
            }
            armRot.position = up(g.pivot)
            shadowMove.position = up(g.pivot)
        }
        CATransaction.commit()
    }

    // MARK: Pose → lagværdier

    private func armScale(_ lift: Double) -> Double { 1 + 0.045 * lift }
    private func shadowOffset(_ lift: Double) -> CGPoint {
        guard let g = geometry else { return .zero }
        let dx = g.h * (0.010 + 0.030 * lift), dy = g.h * (0.016 + 0.045 * lift)
        let p = up(g.pivot)
        return CGPoint(x: p.x + dx, y: p.y - dy)
    }
    private func shadowOpacity(_ lift: Double) -> Double { 0.55 - 0.27 * lift }
    private func shadowScale(_ lift: Double) -> Double { 1 + 0.05 * lift }
    private func rootOpacity(_ idle: Double) -> Double { 1 - 0.22 * idle }

    private func setLabels(_ pose: TurntablePose) {
        guard let g = geometry else { return }
        labelLayer.contents = TurntableImages.label(pose.label, g, scale)
        if let prev = pose.previousLabel {
            previousLabelLayer.contents = TurntableImages.label(prev, g, scale)
        } else {
            previousLabelLayer.contents = nil
        }
    }

    /// Sæt alle modelværdier til en pose (ingen animation).
    func apply(_ pose: TurntablePose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setLabels(pose)
        previousLabelLayer.opacity = Float(pose.previousLabelOpacity)
        rotor.setValue(-pose.recordAngle, forKeyPath: "transform.rotation.z")
        applyNonRotor(pose)
        CATransaction.commit()
    }

    private func applyNonRotor(_ pose: TurntablePose) {
        armRot.setValue(-pose.armAngle, forKeyPath: "transform.rotation.z")
        shadowRot.setValue(-pose.armAngle, forKeyPath: "transform.rotation.z")
        armImage.setValue(armScale(pose.armLift), forKeyPath: "transform.scale")
        shadowImage.setValue(shadowScale(pose.armLift), forKeyPath: "transform.scale")
        shadowImage.opacity = Float(shadowOpacity(pose.armLift))
        shadowMove.position = shadowOffset(pose.armLift)
        previousLabelLayer.opacity = Float(pose.previousLabelOpacity)
        ledGlow.opacity = Float(pose.led)
        root.opacity = Float(rootOpacity(pose.idle))
    }

    // MARK: Live-animation

    /// Fjern alle animationer (fx når vinduet ikke er synligt).
    func stopAnimations() {
        for l in allLayers { l.removeAllAnimations() }
    }

    /// Læg bevægelsen fra `animator` ind som CA-animationer fra tiden `t` (CACurrentMediaTime).
    /// Kaldes kun når tilstanden ændrer sig – ikke pr. billede.
    func sync(_ animator: TurntableAnimator, at t: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stopAnimations()

        // Rotor: rampe (keyframes af den integrerede vinkel) + evt. uendelig jævn omdrejning bagefter.
        let spin = animator.spin
        let rampEnd = max(t, spin.rampEnd)
        if rampEnd > t {
            let times = Self.samples(from: t, to: rampEnd, step: 1.0 / 60)
            let ramp = keyframes(rotor, "transform.rotation.z", times, times.map { -spin.angle(at: $0) }, key: "spinRamp")
            ramp?.fillMode = .forwards
            ramp?.isRemovedOnCompletion = spin.targetVelocity == 0
        }
        if spin.targetVelocity > 0 {
            let a = spin.angle(at: rampEnd)
            let cruise = CABasicAnimation(keyPath: "transform.rotation.z")
            cruise.fromValue = -a
            cruise.toValue = -(a + 2 * .pi)
            cruise.duration = WidgetMetrics.secondsPerRevolution
            cruise.repeatCount = .infinity
            cruise.beginTime = rotor.convertTime(rampEnd, from: nil)
            cruise.fillMode = .forwards
            rotor.add(cruise, forKey: "spinCruise")
            rotor.setValue(-spin.angle(at: t), forKeyPath: "transform.rotation.z")
        } else {
            rotor.setValue(-spin.angle(at: rampEnd), forKeyPath: "transform.rotation.z")
        }

        // Resten: tætte samples gennem overgangene, derefter glisne samples af armens langsomme vej ind over pladen.
        let tEnd = animator.transitionsEnd(after: t)
        let armEnd = animator.armMotionEnd(after: t)
        let dense = Self.samples(from: t, to: tEnd, step: 1.0 / 60)
        let sparseStep = max(1.0, (armEnd - tEnd) / 600)
        let sparse = armEnd > tEnd + 0.01 ? Array(Self.samples(from: tEnd, to: armEnd, step: sparseStep).dropFirst()) : []
        let densePoses = dense.map(animator.pose(at:))
        let armTimes = dense + sparse
        let armPoses = densePoses + sparse.map(animator.pose(at:))

        let now = animator.pose(at: t)
        setLabels(now)
        applyNonRotor(armPoses.last ?? now)

        keyframes(armRot, "transform.rotation.z", armTimes, armPoses.map { -$0.armAngle }, key: "arm")
        keyframes(shadowRot, "transform.rotation.z", armTimes, armPoses.map { -$0.armAngle }, key: "arm")
        keyframes(armImage, "transform.scale", dense, densePoses.map { armScale($0.armLift) }, key: "lift")
        keyframes(shadowImage, "transform.scale", dense, densePoses.map { shadowScale($0.armLift) }, key: "lift")
        keyframes(shadowImage, "opacity", dense, densePoses.map { shadowOpacity($0.armLift) }, key: "liftOpacity")
        keyframes(shadowMove, "position", dense, densePoses.map { NSValue(point: shadowOffset($0.armLift)) }, key: "lift")
        keyframes(previousLabelLayer, "opacity", dense, densePoses.map(\.previousLabelOpacity), key: "fade")
        keyframes(ledGlow, "opacity", dense, densePoses.map(\.led), key: "led")
        keyframes(root, "opacity", dense, densePoses.map { rootOpacity($0.idle) }, key: "idle")
        CATransaction.commit()
    }

    static func samples(from a: Double, to b: Double, step: Double) -> [Double] {
        guard b > a else { return [a] }
        let n = max(1, Int(((b - a) / step).rounded(.up)))
        return (0...n).map { a + (b - a) * Double($0) / Double(n) }
    }

    /// Tilføjer en keyframe-animation hvis værdierne faktisk ændrer sig.
    @discardableResult
    private func keyframes(_ layer: CALayer, _ keyPath: String, _ times: [Double], _ values: [Any], key: String) -> CAKeyframeAnimation? {
        guard times.count >= 2, values.count == times.count, let first = times.first, let last = times.last, last > first else { return nil }
        // NB: [Double] kan bridges til [NSNumber] (= NSValue), så tal tjekkes først og punkter kun hvis det ikke er tal.
        if let nums = values as? [Double] {
            if let lo = nums.min(), let hi = nums.max(), hi - lo < 1e-6 { return nil }
        } else if let pts = values as? [NSValue], Set(pts.map { "\($0.pointValue)" }).count == 1 {
            return nil
        }
        let anim = CAKeyframeAnimation(keyPath: keyPath)
        anim.values = values
        anim.keyTimes = times.map { NSNumber(value: ($0 - first) / (last - first)) }
        anim.duration = last - first
        anim.beginTime = layer.convertTime(first, from: nil)
        anim.calculationMode = .linear
        anim.fillMode = .backwards
        layer.add(anim, forKey: key)
        return anim
    }

    /// Til test: navngivne lag med animationer.
    var debugLayers: [(String, CALayer)] {
        [("rotor", rotor), ("arm", armRot), ("armLøft", armImage), ("skygge", shadowImage), ("skyggeFlyt", shadowMove),
         ("etiket", previousLabelLayer), ("led", ledGlow), ("krop", root)]
    }

    // MARK: Snapshot

    /// Tegner pladespilleren i en given pose til et billede (bruges af SnapshotRenderer – ingen vinduer).
    static func snapshot(_ g: TurntableGeometry, style: TurntableStyle, scale: CGFloat, pose: TurntablePose) -> CGImage? {
        let layer = TurntableLayer()
        layer.configure(g, style: style, scale: scale)
        layer.apply(pose)
        let w = Int(g.size.width * scale), h = Int(g.size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Drawing.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer.root.render(in: ctx)   // render(in:) tager selv højde for opacity og affine transformationer
        return ctx.makeImage()
    }
}
