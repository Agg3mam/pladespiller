import Foundation

/// Bevægelsen beskrives analytisk som funktioner af tid (sekunder, samme ur som `CACurrentMediaTime`).
/// Live: funktionerne samples og gives til Core Animation som keyframes (render-serveren kører dem).
/// Snapshots/test: funktionerne evalueres direkte til et vilkårligt tidspunkt.

@inline(__always) func easeInOut(_ s: Double) -> Double {
    let t = min(max(s, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Pladens rotation. Hastigheden easer (smoothstep) mellem to værdier; vinklen er integralet,
/// så både vinkel og hastighed er kontinuerte – også når man skifter mål midt i en op/nedbremsning.
struct SpinMotion: Equatable {
    /// Reference-fart (standard) til at skalere rampernes længde. Den faktiske fart vælges i indstillingerne.
    static let referenceCruise = 2 * Double.pi / WidgetMetrics.secondsPerRevolution   // rad/s
    static func cruise(secondsPerRevolution s: Double) -> Double { 2 * Double.pi / s }

    private(set) var t0: Double = 0
    private(set) var a0: Double = 0
    private(set) var v0: Double = 0
    private(set) var v1: Double = 0
    private(set) var duration: Double = 0

    var rampEnd: Double { t0 + duration }
    var targetVelocity: Double { v1 }

    func velocity(at t: Double) -> Double {
        guard duration > 0 else { return v1 }
        let s = (t - t0) / duration
        if s <= 0 { return v0 }
        if s >= 1 { return v1 }
        return v0 + (v1 - v0) * easeInOut(s)
    }

    func angle(at t: Double) -> Double {
        let dt = t - t0
        if dt <= 0 { return a0 + v0 * dt }
        if duration <= 0 || dt >= duration {
            return a0 + (v0 + v1) / 2 * duration + v1 * (dt - duration)
        }
        let s = dt / duration
        // ∫ smoothstep = s³ - s⁴/2
        return a0 + v0 * dt + (v1 - v0) * duration * (s * s * s - s * s * s * s / 2)
    }

    /// Skift mål-hastighed til tiden `t`. Varigheden er proportional med hastighedsændringen
    /// (fuld op = 0,8 s, fuld ned = 1,2 s), så en afbrudt opspeedning bremser kortere.
    mutating func setTarget(_ v: Double, at t: Double) {
        guard v != v1 else { return }
        let a = angle(at: t), cv = velocity(at: t)
        let base = v > cv ? WidgetMetrics.spinUpDuration : WidgetMetrics.spinDownDuration
        t0 = t
        a0 = a.truncatingRemainder(dividingBy: 2 * .pi)
        v0 = cv
        v1 = v
        // Fuld op/ned fra stilstand som før; skift mellem to farter (33 ↔ 45) mindst 0,5 s, så det ses som en blød overgang.
        duration = base * abs(v - cv) / Self.referenceCruise
        if cv > 0, v > 0 { duration = max(duration, 0.5) }
    }

    /// Stil direkte (uden rampe), fx første gang.
    mutating func jump(to v: Double, at t: Double) {
        let a = angle(at: t)
        t0 = t; a0 = a.truncatingRemainder(dividingBy: 2 * .pi); v0 = v; v1 = v; duration = 0
    }
}

/// Simpel tidsbaseret overgang mellem to tal.
struct Fade: Equatable {
    var from: Double
    var to: Double
    var start: Double = 0
    var duration: Double = 0
    var delay: Double = 0

    init(_ value: Double) { from = value; to = value }

    func value(at t: Double) -> Double {
        guard duration > 0 else { return to }
        return from + (to - from) * easeInOut((t - start - delay) / duration)
    }

    var end: Double { start + delay + duration }

    mutating func set(_ v: Double, at t: Double, duration d: Double, delay: Double = 0) {
        guard v != to else { return }
        from = value(at: t); to = v; start = t; duration = d; self.delay = delay
    }
}

/// Input til pladespilleren (afledt af `NowPlaying`). `position` er målt til tidspunktet for opdateringen.
struct TurntableInput: Equatable {
    var trackKey: String
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var label: LabelContent

    init(_ np: NowPlaying, at date: Date) {
        trackKey = np.trackKey
        isPlaying = np.isPlaying
        position = np.position(at: date)
        duration = np.duration
        label = LabelContent(np)
    }
}

/// Alt hvad der skal til for at tegne pladespilleren til et bestemt tidspunkt.
struct TurntablePose: Equatable {
    var recordAngle: Double = 0      // rad, med uret
    var armAngle: Double = 0         // rad, med uret (y nedad)
    var armLift: Double = 0          // 0 = på pladen/hvilestøtten, 1 = løftet
    var label: LabelContent = .blank
    var previousLabel: LabelContent?
    var previousLabelOpacity: Double = 0
    var led: Double = 0              // 0...1
    var idle: Double = 1             // 1 = intet spiller (dæmpet)
    var fortyFive = false            // 45-knappen trykket ned (ellers 33)
}

/// Tilstandsmaskinen. Ren Swift uden Core Animation, så den kan testes og tegnes til et givet tidspunkt.
struct TurntableAnimator {
    let geometry: TurntableGeometry

    private(set) var spin = SpinMotion()
    private(set) var input: TurntableInput?
    private var inputTime: Double = 0

    // Arm
    private enum ArmTarget: Equatable { case rest, groove }
    private var armTarget: ArmTarget = .rest
    private var armTransition: (start: Double, duration: Double, fromAngle: Double, fromLift: Double, lift: Double, glide: Bool)?
    /// Små rettelser af målet (fx musikappens bekræftelse midt i en bevægelse): i stedet for at starte bevægelsen forfra
    /// (så armen bremser brat op og starter igen) lægges forskellen oven i og tones blødt ud. Vinkel og fart er kontinuerte.
    private var armCorrections: [(start: Double, amount: Double)] = []

    // Etiket
    private(set) var label: LabelContent = .blank
    private var previousLabel: LabelContent?
    private var labelFade = Fade(0)

    /// Valgt fart (rad/s) mens der spilles – fra `settings.spinSpeed`.
    private(set) var cruiseVelocity = SpinMotion.referenceCruise
    /// Hvilken af kroppens hastighedsknapper der er trykket ned.
    private(set) var fortyFive = false

    /// Ny hastighed fra indstillingerne. Spiller pladen, speeder den blødt op/ned (samme rampe, kontinuert vinkel og fart).
    @discardableResult
    mutating func setSpeed(_ speed: SpinSpeed, at t: Double) -> Bool {
        let v = SpinMotion.cruise(secondsPerRevolution: speed.secondsPerRevolution)
        guard v != cruiseVelocity || speed.isFortyFive != fortyFive else { return false }
        cruiseVelocity = v
        fortyFive = speed.isFortyFive
        if started, input?.isPlaying == true { spin.setTarget(v, at: t) }
        return true
    }

    private var led = Fade(0)
    private var idle = Fade(1)
    /// Brugeren trækker på fremdriftslinjen: spring følges glidende og uden løft.
    var scrubbing = false
    static let glideDuration = 0.22
    private var started = false

    init(geometry: TurntableGeometry) {
        self.geometry = geometry
    }

    /// Ny geometri (størrelse) men samme tilstand.
    func with(geometry g: TurntableGeometry) -> TurntableAnimator {
        var copy = TurntableAnimator(geometry: g)
        copy.spin = spin; copy.input = input; copy.inputTime = inputTime
        copy.armTarget = armTarget; copy.armTransition = armTransition; copy.armCorrections = armCorrections; copy.dropSpring = dropSpring
        copy.label = label; copy.previousLabel = previousLabel; copy.labelFade = labelFade
        copy.led = led; copy.idle = idle; copy.started = started
        copy.cruiseVelocity = cruiseVelocity; copy.fortyFive = fortyFive
        return copy
    }

    /// Forventet position (sek.) i den aktuelle sang til tiden t.
    func expectedPosition(at t: Double) -> Double? {
        guard let input else { return nil }
        var p = input.position + (input.isPlaying ? t - inputTime : 0)
        if input.duration > 0 { p = min(p, input.duration) }
        return max(0, p)
    }

    func grooveAngle(at t: Double) -> Double {
        guard let input, input.duration > 0, let p = expectedPosition(at: t) else {
            return Double(geometry.armAngle(forProgress: 0))
        }
        return Double(geometry.armAngle(forProgress: p / input.duration))
    }

    private func armTargetAngle(at t: Double) -> Double {
        armTarget == .rest ? Double(geometry.restAngle) : grooveAngle(at: t)
    }

    /// Opdater med nyt input til tiden t. Returnerer true hvis noget ændrede sig (så animationerne skal lægges om).
    @discardableResult
    mutating func update(_ new: TurntableInput?, at t: Double) -> Bool {
        let old = input
        if started, old == nil, new == nil { return false }
        if started, let old, let new, old.trackKey == new.trackKey, old.isPlaying == new.isPlaying,
           old.duration == new.duration, old.label == new.label,
           let exp = expectedPosition(at: t), abs(exp - new.position) < (scrubbing ? 0.2 : 1.0) {
            return false   // samme tilstand, kun lidt drift (under scrub følges også små flyt)
        }

        let trackChanged = old?.trackKey != new?.trackKey
        // Spring i sangen: stort (≥ 3 s, ikke under scrub) løfter armen kort; små spring og alt under scrub glider armen
        // blødt hen uden løft, så den hverken hopper eller springer tilbage.
        let jump: Double = {
            guard let old, let new, !trackChanged, old.isPlaying, new.isPlaying, let exp = expectedPosition(at: t) else { return 0 }
            return abs(exp - new.position)
        }()
        let seek = jump >= 3.0 && !scrubbing
        let glide = jump > 0 && !seek
        let newArmTarget: ArmTarget = (new?.isPlaying == true) ? .groove : .rest
        let currentPose = pose(at: t)
        let oldTargetAngle = armTargetAngle(at: t)
        armCorrections.removeAll { t >= $0.start + Self.glideDuration }

        input = new
        inputTime = t

        let playing = new?.isPlaying == true
        if !started {
            started = true
            spin.jump(to: playing ? cruiseVelocity : 0, at: t)
            armTarget = newArmTarget
            label = new?.label ?? .blank
            led = Fade(playing ? 1 : 0)
            idle = Fade(new == nil ? 1 : 0)
            return true
        }

        spin.setTarget(playing ? cruiseVelocity : 0, at: t)
        led.set(playing ? 1 : 0, at: t, duration: 0.3)
        idle.set(new == nil ? 1 : 0, at: t, duration: 0.5)

        let D = WidgetMetrics.trackChangeDuration
        let newLabel = new?.label ?? .blank
        if newLabel != label {
            previousLabel = currentPose.previousLabelOpacity > 0.5 ? currentPose.previousLabel : label
            label = newLabel
            labelFade = Fade(1)
            labelFade.set(0, at: t, duration: D * 0.7, delay: D * 0.12)
        }

        let armNeedsMove = newArmTarget != armTarget || (trackChanged && newArmTarget == .groove) || seek
        if glide, !armNeedsMove, let tr = armTransition, t < tr.start + tr.duration {
            // Midt i en bevægelse: den fortsætter uforstyrret mod det nye mål; forskellen tones ud ovenpå.
            let w = targetWeight(tr, at: t)
            armTarget = newArmTarget
            let amount = (oldTargetAngle - armTargetAngle(at: t)) * w
            if abs(amount) > 1e-9 { armCorrections.append((t, amount)) }
            return true
        } else if glide, !armNeedsMove {
            // Glid fra den nuværende vinkel til den nye uden løft.
            armTransition = (t, Self.glideDuration, currentPose.armAngle, currentPose.armLift, 0, true)
            armCorrections = []
            dropSpring = false
        } else if armNeedsMove {
            // Løft lidt ved pause/afspil, lidt mere ved ny sang.
            let lift: Double = trackChanged || seek ? 1.0 : 0.8
            // Selve flytningen er færdig på under 1 s; resten er nålen, der fjedrer til ro.
            let dur = (seek ? D * 0.7 : D) * Self.springStretch
            armTransition = (t, dur, currentPose.armAngle, currentPose.armLift, lift, false)
            armCorrections = []
            dropSpring = false
        }
        armTarget = newArmTarget
        return true
    }

    /// Brugeren slipper armen ved `angle` (løftet `lift`): den sænkes blødt derfra og glider til sin plads
    /// (rillen ved den nye position, eller hvilestøtten ved pause).
    mutating func dropArm(from angle: Double, lift: Double, at t: Double) {
        armTransition = (t, Self.dropDuration, angle, lift, 0, true)
        armCorrections = []
        dropSpring = true
    }
    /// Slip: armen glider på plads og sænkes på `dropMove` (som før), og fjedrer derefter til ro i `dropTail`.
    static let dropMove = 0.35
    static let dropTail = 0.4
    static let dropDuration = dropMove + dropTail
    /// Hvor højt nålen hopper efter et slip (i løft, 0...1).
    static let dropBounce = 0.12
    /// Armen er sluppet fra hånden og fjedrer til sidst (kun det glid, `dropArm` har startet).
    private var dropSpring = false

    /// Nålens hop efter landingen (v = 0...1 gennem halen): to hop, det andet meget lavere.
    static func hops(_ v: Double) -> Double {
        guard v > 0, v < 1 else { return 0 }
        let wave = sin(.pi * 1.5 * v)
        return exp(-2.6 * v) * wave * wave * (1 - v * v * v)
    }
    /// Hvor meget længere en arm-bevægelse varer, fordi den slutter med at fjedre.
    static let springStretch = 1.3

    /// Tidspunktet hvor alle korte overgange er færdige.
    func transitionsEnd(after t: Double) -> Double {
        var end = max(spin.rampEnd, labelFade.end, led.end, idle.end)
        if let tr = armTransition { end = max(end, tr.start + tr.duration) }
        for c in armCorrections { end = max(end, c.start + Self.glideDuration) }
        return max(end, t)
    }

    /// Hvornår armen holder op med at bevæge sig (sangens slutning mens der spilles).
    func armMotionEnd(after t: Double) -> Double {
        let end = transitionsEnd(after: t)
        guard armTarget == .groove, let input, input.isPlaying, input.duration > 0,
              let p = expectedPosition(at: t) else { return end }
        return max(end, t + (input.duration - p))
    }

    /// Hvor meget målet vægter i armens vinkel midt i en overgang (0 = startvinklen, 1 = målet).
    private func targetWeight(_ tr: (start: Double, duration: Double, fromAngle: Double, fromLift: Double, lift: Double, glide: Bool),
                              at t: Double) -> Double {
        let s = (t - tr.start) / tr.duration
        if s >= 1 { return 1 }
        if tr.glide { return easeInOut(min(1, s / glideMove)) }
        if s < 0.12 { return 0 }
        if s < 0.46 { return Self.swing((s - 0.12) / 0.34) }
        return 1
    }

    /// Den del af et glid, hvor armen flytter sig og sænkes (resten er fjederen efter et slip).
    private var glideMove: Double { dropSpring ? Self.dropMove / Self.dropDuration : 1 }

    /// Summen af de rettelser, der stadig tones ud.
    private func correction(at t: Double) -> Double {
        armCorrections.reduce(0) { sum, c in
            let s = (t - c.start) / Self.glideDuration
            return s >= 1 ? sum : sum + c.amount * (1 - easeInOut(s))
        }
    }

    /// Armen sænkes og fjedrer: 1 → 0. Den falder blødt ned til pladen (ved `touch`), og så giver armens ophæng efter:
    /// nålen hopper et par gange op igen, hver gang lavere, før den ligger stille – som på en rigtig pladespiller.
    /// Værdien er sammenhængende, og farten er nul i begge ender (intet ryk).
    static func springLanding(_ u: Double, touch: Double = 0.55, bounce: Double = 0.14) -> Double {
        let u = min(max(u, 0), 1)
        if u < touch { return 1 - easeInOut(pow(u / touch, 0.8)) }
        let v = (u - touch) / (1 - touch)                  // 0...1 efter at nålen har ramt
        let hops = 1.5                                     // ét lille hop og et næsten usynligt efterslæb
        let wave = sin(.pi * hops * v)
        return bounce * exp(-3.2 * v) * wave * wave * (1 - v * v * v)
    }

    /// Armens vej hen over pladen (0 → 1): den svinger en anelse for langt og falder tilbage (den har vægt).
    static func swing(_ s: Double) -> Double {
        let t = min(max(s, 0), 1)
        let over = 0.012, turn = 0.78
        if t < turn { return (1 + over) * easeInOut(t / turn) }
        return 1 + over * (1 - easeInOut((t - turn) / (1 - turn)))
    }

    func pose(at t: Double) -> TurntablePose {
        var p = basePose(at: t)
        p.armAngle += correction(at: t)
        return p
    }

    /// Posen uden rettelserne.
    private func basePose(at t: Double) -> TurntablePose {
        var p = TurntablePose()
        p.recordAngle = spin.angle(at: t)
        p.fortyFive = fortyFive
        p.label = label
        let fade = labelFade.value(at: t)
        if fade > 0.001, let previousLabel { p.previousLabel = previousLabel; p.previousLabelOpacity = fade }
        p.led = led.value(at: t)
        p.idle = idle.value(at: t)

        let target = armTargetAngle(at: t)
        if let tr = armTransition, t < tr.start + tr.duration {
            let s = (t - tr.start) / tr.duration
            if tr.glide {
                // Glid: armen flyttes straks og blødt; et evt. løft fra før sænkes samtidig.
                let e = easeInOut(min(1, s / glideMove))
                p.armAngle = tr.fromAngle + (target - tr.fromAngle) * e
                p.armLift = tr.fromLift * (1 - e)
                // Sluppet fra hånden: når armen er nede, fjedrer nålen et par gange, før den ligger stille.
                if dropSpring, s > glideMove { p.armLift = Self.dropBounce * Self.hops((s - glideMove) / (1 - glideMove)) }
                return p
            }
            // løft 0–15 %, flyt 12–46 %, sænk og fjedr 40–100 %
            if s < 0.15 { p.armLift = tr.fromLift + (tr.lift - tr.fromLift) * easeInOut(s / 0.15) }
            else if s < 0.40 { p.armLift = tr.lift }
            else { p.armLift = tr.lift * Self.springLanding((s - 0.40) / 0.60) }
            if s < 0.12 { p.armAngle = tr.fromAngle }
            else if s < 0.46 { p.armAngle = tr.fromAngle + (target - tr.fromAngle) * Self.swing((s - 0.12) / 0.34) }
            else { p.armAngle = target }
        } else {
            p.armAngle = target
            p.armLift = 0
        }
        return p
    }
}
