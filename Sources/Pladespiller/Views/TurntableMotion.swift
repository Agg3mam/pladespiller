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
    static let cruise = 2 * Double.pi / WidgetMetrics.secondsPerRevolution   // rad/s

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
        duration = base * abs(v - cv) / Self.cruise
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
    private var armTransition: (start: Double, duration: Double, fromAngle: Double, fromLift: Double, lift: Double)?

    // Etiket
    private(set) var label: LabelContent = .blank
    private var previousLabel: LabelContent?
    private var labelFade = Fade(0)

    private var led = Fade(0)
    private var idle = Fade(1)
    private var started = false

    init(geometry: TurntableGeometry) {
        self.geometry = geometry
    }

    /// Ny geometri (størrelse) men samme tilstand.
    func with(geometry g: TurntableGeometry) -> TurntableAnimator {
        var copy = TurntableAnimator(geometry: g)
        copy.spin = spin; copy.input = input; copy.inputTime = inputTime
        copy.armTarget = armTarget; copy.armTransition = armTransition
        copy.label = label; copy.previousLabel = previousLabel; copy.labelFade = labelFade
        copy.led = led; copy.idle = idle; copy.started = started
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
           let exp = expectedPosition(at: t), abs(exp - new.position) < 1.0 {
            return false   // samme tilstand, kun lidt drift
        }

        let trackChanged = old?.trackKey != new?.trackKey
        let seek: Bool = {
            guard let old, let new, !trackChanged, old.isPlaying, new.isPlaying, let exp = expectedPosition(at: t) else { return false }
            return abs(exp - new.position) >= 3.0
        }()
        let newArmTarget: ArmTarget = (new?.isPlaying == true) ? .groove : .rest
        let currentPose = pose(at: t)

        input = new
        inputTime = t

        let playing = new?.isPlaying == true
        if !started {
            started = true
            spin.jump(to: playing ? SpinMotion.cruise : 0, at: t)
            armTarget = newArmTarget
            label = new?.label ?? .blank
            led = Fade(playing ? 1 : 0)
            idle = Fade(new == nil ? 1 : 0)
            return true
        }

        spin.setTarget(playing ? SpinMotion.cruise : 0, at: t)
        led.set(playing ? 1 : 0, at: t, duration: 0.3)
        idle.set(new == nil ? 1 : 0, at: t, duration: 0.5)

        let D = WidgetMetrics.trackChangeDuration
        let newLabel = new?.label ?? .blank
        if newLabel != label {
            previousLabel = currentPose.previousLabelOpacity > 0.5 ? currentPose.previousLabel : label
            label = newLabel
            labelFade = Fade(1)
            labelFade.set(0, at: t, duration: D * 0.5, delay: D * 0.15)
        }

        let armNeedsMove = newArmTarget != armTarget || (trackChanged && newArmTarget == .groove) || seek
        if armNeedsMove {
            // Løft lidt ved pause/afspil, lidt mere ved ny sang.
            let lift: Double = trackChanged || seek ? 1.0 : 0.8
            let dur = seek ? D * 0.7 : D
            armTransition = (t, dur, currentPose.armAngle, currentPose.armLift, lift)
        }
        armTarget = newArmTarget
        return true
    }

    /// Tidspunktet hvor alle korte overgange er færdige.
    func transitionsEnd(after t: Double) -> Double {
        var end = max(spin.rampEnd, labelFade.end, led.end, idle.end)
        if let tr = armTransition { end = max(end, tr.start + tr.duration) }
        return max(end, t)
    }

    /// Hvornår armen holder op med at bevæge sig (sangens slutning mens der spilles).
    func armMotionEnd(after t: Double) -> Double {
        let end = transitionsEnd(after: t)
        guard armTarget == .groove, let input, input.isPlaying, input.duration > 0,
              let p = expectedPosition(at: t) else { return end }
        return max(end, t + (input.duration - p))
    }

    func pose(at t: Double) -> TurntablePose {
        var p = TurntablePose()
        p.recordAngle = spin.angle(at: t)
        p.label = label
        let fade = labelFade.value(at: t)
        if fade > 0.001, let previousLabel { p.previousLabel = previousLabel; p.previousLabelOpacity = fade }
        p.led = led.value(at: t)
        p.idle = idle.value(at: t)

        let target = armTargetAngle(at: t)
        if let tr = armTransition, t < tr.start + tr.duration {
            let s = (t - tr.start) / tr.duration
            // løft 0–28 %, flyt 22–78 %, sænk 72–100 %
            if s < 0.28 { p.armLift = tr.fromLift + (tr.lift - tr.fromLift) * easeInOut(s / 0.28) }
            else if s < 0.72 { p.armLift = tr.lift }
            else { p.armLift = tr.lift * (1 - easeInOut((s - 0.72) / 0.28)) }
            if s < 0.22 { p.armAngle = tr.fromAngle }
            else if s < 0.78 { p.armAngle = tr.fromAngle + (target - tr.fromAngle) * easeInOut((s - 0.22) / 0.56) }
            else { p.armAngle = target }
        } else {
            p.armAngle = target
            p.armLift = 0
        }
        return p
    }
}
