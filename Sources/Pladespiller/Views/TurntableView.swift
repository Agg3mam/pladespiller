import AppKit
import QuartzCore
import SwiftUI

/// I snapshots: tegn pladespilleren i denne pose i stedet for den levende CA-visning.
struct TurntableSnapshotPose {
    var pose: TurntablePose
    var dim: Double = 0
}

private struct TurntableSnapshotKey: EnvironmentKey {
    static let defaultValue: TurntableSnapshotPose? = nil
}

extension EnvironmentValues {
    var turntableSnapshot: TurntableSnapshotPose? {
        get { self[TurntableSnapshotKey.self] }
        set { self[TurntableSnapshotKey.self] = newValue }
    }
}

/// Pladespilleren set ovenfra. Live: et NSView med Core Animation-lag. Snapshot: et stillbillede af samme lag.
struct TurntableView: View {
    let size: CGSize
    var cornerRadius: CGFloat = 20
    var deck: CGRect? = nil
    let theme: TurntableTheme
    var flatColor: FlatColor = .auto
    var flatCustomHex: String = "F2B705"
    let nowPlaying: NowPlaying?
    var dim: Double = 0
    var speed: SpinSpeed = .calm
    var scrubbing = false
    /// Fuld skærm: kroppen som én ren farve.
    var solidBody = false
    /// Fuld skærm: armstøtte, 33/45-knapper og LED.
    var deckDetails = false
    var onArmClick: () -> Void = {}
    var onRecordClick: () -> Void = {}
    var onSpeedClick: (SpinSpeed) -> Void = { _ in }
    /// Armen er trukket hen til fremdrift 0...1 og sluppet: spol dertil. nil = armen kan ikke trækkes.
    var onArmSeek: ((Double) -> Void)? = nil

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.widgetDragClaim) private var dragClaim
    @Environment(\.displayScale) private var displayScale

    var geometry: TurntableGeometry { TurntableGeometry(size: size, cornerRadius: cornerRadius, deck: deck, flat: theme == .flat) }
    var style: TurntableStyle {
        TurntableStyle.make(theme: theme, artwork: nowPlaying?.artwork, flatColor: flatColor, customHex: flatCustomHex, solidBody: solidBody,
                            deckDetails: deckDetails)
    }

    var body: some View {
        Group {
            if let snapshot {
                if let cg = TurntableLayer.snapshot(geometry, style: style, scale: displayScale, pose: snapshot.pose, dim: snapshot.dim) {
                    Image(decorative: cg, scale: displayScale)
                        .resizable()
                }
            } else {
                LiveTurntable(geometry: geometry, style: style, nowPlaying: nowPlaying, dim: dim, speed: speed, scrubbing: scrubbing,
                              onArmClick: onArmClick, onRecordClick: onRecordClick, onSpeedClick: onSpeedClick,
                              onArmSeek: (nowPlaying?.duration ?? 0) > 0 ? onArmSeek : nil, dragClaim: dragClaim)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: nowPlaying?.isPlaying == true ? "Pause" : L("Afspil", "Play"), onArmClick)
        .accessibilityAction(named: L("Åbn musikappen", "Open the music app"), onRecordClick)
    }

    private var accessibilityText: String {
        guard let np = nowPlaying else { return L("Pladespiller. Intet spiller", "Turntable. Nothing playing") }
        return L("Pladespiller", "Turntable") + ". \(np.isPlaying ? L("Spiller", "Playing") : L("På pause", "Paused")): \(TrackStrings.title(np)) \(L("af", "by")) \(TrackStrings.artist(np))"
    }
}

private struct LiveTurntable: NSViewRepresentable {
    let geometry: TurntableGeometry
    let style: TurntableStyle
    let nowPlaying: NowPlaying?
    let dim: Double
    let speed: SpinSpeed
    let scrubbing: Bool
    let onArmClick: () -> Void
    let onRecordClick: () -> Void
    let onSpeedClick: (SpinSpeed) -> Void
    let onArmSeek: ((Double) -> Void)?
    let dragClaim: WidgetDragClaim?

    func makeNSView(context: Context) -> TurntableNSView { TurntableNSView() }

    func updateNSView(_ view: TurntableNSView, context: Context) {
        view.onArmClick = onArmClick
        view.onRecordClick = onRecordClick
        view.onSpeedClick = onSpeedClick
        view.onArmSeek = onArmSeek
        view.dragClaim = dragClaim
        view.configure(geometry: geometry, style: style)
        view.setSpeed(speed)
        view.setScrubbing(scrubbing)
        view.update(nowPlaying)
        view.setDim(dim)
    }
}

/// Holder lagtræet og tilstandsmaskinen. Gør kun noget når input faktisk ændrer sig.
final class TurntableNSView: NSView {
    private let turntable = TurntableLayer()
    private var animator: TurntableAnimator?
    private var geometry: TurntableGeometry?
    private var style: TurntableStyle?
    private var visible = true
    private weak var observedWindow: NSWindow?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(turntable.container)   // N1: hele træet inkl. dæmpningslaget (samme som snapshots)
        WoodTexture.prewarm()
        NotificationCenter.default.addObserver(self, selector: #selector(woodLoaded), name: WoodTexture.didLoad, object: nil)
        // N13: panelet bliver aldrig key, så cursor styres med et tracking area der altid er aktivt.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @objc private func woodLoaded() { rebuild() }

    /// Kun test (ArmDragTest): lagene, så det viste billede kan aflæses.
    var debugTurntable: TurntableLayer { turntable }
    var debugAnimator: TurntableAnimator? { animator }

    /// Kun test (LiveSequenceTest): efterlign QA-fejlen N2.
    var debugFreezeAfterSync = false

    /// Sikkerhedsnet (QA N2): sæt sluttilstanden når overgangene er færdige. Én planlagt opgave ad gangen.
    private var settleWork: DispatchWorkItem?
    private func scheduleSettle(after delay: Double) {
        settleWork?.cancel()
        guard delay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                // Mens armen holdes, styrer hånden løftet; sikkerhedsnettet lægges ind igen ved slip.
                guard let self, let animator = self.animator, self.visible, self.armHold == nil else { return }
                self.turntable.settle(animator, at: CACurrentMediaTime())
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.15, execute: work)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { Self.setCursor(.arrow) }

    /// Sætter cursoren. Testen (ArmDragTest) slår den fra: den må ikke ændre brugerens cursor (og den er langsom).
    static var setCursor: (NSCursor) -> Void = { $0.set() }

    private func updateCursor(_ event: NSEvent) {
        if armHold != nil { Self.setCursor(.closedHand); return }
        let over = target(at: convert(event.locationInWindow, from: nil)) != nil
        Self.setCursor(over ? .pointingHand : .arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    var onArmClick: () -> Void = {}
    var onRecordClick: () -> Void = {}
    var onSpeedClick: (SpinSpeed) -> Void = { _ in }
    var onArmSeek: ((Double) -> Void)?
    /// Widgettens krav på musen: når armen trækkes, må panelet ikke flytte sig.
    weak var dragClaim: WidgetDragClaim?

    // MARK: Klik
    //
    // Kun armen og pladen tager imod klik; alt andet går videre (nil), så vinduet kan trækkes derfra.
    // Træk længere end 4 pt overtages af panelet, som afslutter med et mouseUp langt uden for vinduet –
    // så bliver et træk aldrig til et klik.

    private enum Target: Equatable { case arm, record, speed(SpinSpeed) }
    private var pressed: Target?

    private func target(at local: NSPoint) -> Target? {
        guard let g = geometry else { return nil }
        let p = CGPoint(x: local.x, y: bounds.height - local.y)          // y nedad som geometrien
        // 33/45-knapperne: små, så klikfladen er mindst 14 pt i diameter.
        let hitR = max(g.speedButtonRadius, 7)
        for (i, c) in g.speedButtons.enumerated() where style?.deckDetails == true && hypot(p.x - c.x, p.y - c.y) <= hitR {
            return .speed(i == 0 ? .rpm33 : .rpm45)
        }
        // Armen (ved sin vinkel lige nu)
        let a = shownArm().angle
        let dx = p.x - g.pivot.x, dy = p.y - g.pivot.y
        let lx = dx * cos(a) + dy * sin(a), ly = -dx * sin(a) + dy * cos(a)
        let slack: CGFloat = 5
        if lx > g.counterweightEnd - slack, lx < g.tubeLength + g.headshellLength + slack {
            let halfWidth = lx > g.tubeLength * 0.95 ? g.headshellWidth + slack : max(g.counterweightRadius, g.tubeWidth) + slack
            let mid: CGFloat = lx > g.tubeLength ? (lx - g.tubeLength) * tan(g.headshellAngle) : 0
            if abs(ly - mid) < halfWidth { return .arm }
        }
        if hypot(p.x - g.center.x, p.y - g.center.y) < g.recordRadius { return .record }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let local = convert(point, from: sv)
        return target(at: local) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// "Åbn som vindue" kan flyttes ved at trække i baggrunden – men ikke i armen eller pladen.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        pressed = target(at: local)
        armHold = nil
        guard pressed == .arm, onArmSeek != nil, let g = geometry else { return }
        // Armen gribes med det samme: den løftes blødt og står stille (og musikken holder pause), præcis som når
        // man løfter armen på en rigtig pladespiller. Hold fast i det sted på armen, man tog fat.
        let t = CACurrentMediaTime()
        let shown = shownArm(at: t)
        let a = shown.angle
        let wasPlaying = animator?.input?.isPlaying == true
        armHold = ArmHold(start: local, grab: Self.wrap(mouseAngle(local, g) - a), angle: a, startAngle: a,
                          liftFrom: shown.lift, liftStart: t, pausedOnPress: wasPlaying)
        dragClaim?.isClaimed = true          // et træk i armen flytter ikke widgetten
        Self.setCursor(.closedHand)
        // Pause med det samme i animationen (pladen bremser op), uden at vente på musikappens svar.
        if wasPlaying, var input = animator?.input {
            input.position = animator?.expectedPosition(at: t) ?? input.position
            input.isPlaying = false
            animator?.update(input, at: t)
        }
        expect(playing: false, position: nil, until: .infinity)
        if wasPlaying { onArmClick() }      // pause nu (et klik giver alligevel pause)
        if animator != nil { resync(at: t) } else { applyHold() }     // armen i hånden (resten kører videre)
    }

    // MARK: Grib og træk i armen = spol
    //
    // Tryk: armen løftes blødt og står stille, musikken holder pause. Træk: armen følger musen hen over rillerne.
    // Slip: armen sænkes, der spoles dertil, og musikken fortsætter (hvis den spillede). Slip uden træk = et klik.

    private struct ArmHold {
        var start: NSPoint
        var grab: Double
        var angle: Double
        /// Vinklen hvor armen blev grebet (fx på støtten): armen kan føres derhen igen uden at springe.
        var startAngle: Double
        var liftFrom: Double
        var liftStart: Double
        var pausedOnPress: Bool
        var moved = false
    }
    private var armHold: ArmHold?
    private static let holdLift = 0.7
    private static let liftDuration = 0.2

    /// Løftet under et greb til tiden t: blød ease-out fra `liftFrom` til `holdLift` over `liftDuration`.
    /// Var armen allerede løftet mere (fx på vej mod støtten), bliver den deroppe – den dykker ikke.
    private func holdLift(_ h: ArmHold, at t: Double) -> Double {
        let s = min(1, max(0, (t - h.liftStart) / Self.liftDuration))
        let e = 1 - (1 - s) * (1 - s)
        return h.liftFrom + (max(Self.holdLift, h.liftFrom) - h.liftFrom) * e
    }

    /// Læg grebet (vinkel + resten af løftet) ind igen, fx efter at alle animationer er lagt om.
    /// Tiden tages først nu: kurven skal passe til det øjeblik, animationen faktisk starter (ellers et lille dyk).
    private func applyHold() {
        let t = CACurrentMediaTime()
        guard let h = armHold else { return }
        let remaining = max(0, h.liftStart + Self.liftDuration - t)
        turntable.holdArm(angle: h.angle, duration: remaining) { [h] dt in self.holdLift(h, at: t + dt) }
    }

    /// Armens vinkel og løft, som de vises til tiden t – regnet ud (i hånden, eller animatorens bevægelse) i stedet for
    /// at spørge præsentationslaget. Præsentationslaget gemmes pr. CA-transaktion og kan være et øjeblik bagud; grebet
    /// skal starte præcis på den kurve, animationerne er lavet af (ellers et lille hop i løftet eller vinklen).
    private func shownArm(at t: Double = CACurrentMediaTime()) -> (angle: Double, lift: Double) {
        if let h = armHold { return (h.angle, holdLift(h, at: t)) }
        if let animator {
            let p = animator.pose(at: t)
            return (p.armAngle, p.armLift)
        }
        return (turntable.visibleArmAngle(), turntable.visibleArmLift())
    }

    private func mouseAngle(_ local: NSPoint, _ g: TurntableGeometry) -> Double {
        let p = CGPoint(x: local.x, y: bounds.height - local.y)          // y nedad som geometrien
        return Double(atan2(p.y - g.pivot.y, p.x - g.pivot.x))
    }

    private static func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    /// Armvinklen for musen, klemt til rillerne (yderste … inderste) – eller til der, hvor armen blev grebet, hvis det var
    /// uden for rillerne (fx på støtten), så den ikke springer ind på pladen ved første træk. Og fremdriften der hører til.
    private func armPosition(_ local: NSPoint, _ h: ArmHold, _ g: TurntableGeometry) -> (angle: Double, progress: Double) {
        let raw = h.angle + Self.wrap(mouseAngle(local, g) - h.grab - h.angle)
        let a0 = Double(g.armAngle(forProgress: 0)), a1 = Double(g.armAngle(forProgress: 1))
        let lo = min(a0, a1, h.startAngle), hi = max(a0, a1, h.startAngle)
        let angle = min(max(raw, lo), hi)
        return (angle, g.progress(forArmAngle: CGFloat(angle)))
    }

    override func mouseDragged(with event: NSEvent) {
        guard var h = armHold, let g = geometry else { return }
        let local = convert(event.locationInWindow, from: nil)
        // Armen følger musen fra første punkt (ellers hopper den op til 3 pt, når grænsen nås). Grænsen afgør kun,
        // om det er et træk (spol) eller et klik.
        if !h.moved, hypot(local.x - h.start.x, local.y - h.start.y) > 3 { h.moved = true }
        h.angle = armPosition(local, h, g).angle
        armHold = h
        turntable.moveHeldArm(angle: h.angle)        // kun vinklen: løftet kører videre uden at starte forfra
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; armHold = nil; dragClaim?.isClaimed = false }
        let local = convert(event.locationInWindow, from: nil)
        if let h = armHold, let g = geometry, animator != nil {
            let t = CACurrentMediaTime()
            let progress = armPosition(local, h, g).progress
            let play = h.moved ? h.pausedOnPress : !h.pausedOnPress && bounds.contains(local)
            // Fortæl straks animationen, hvad der sker (ny position, afspil eller pause), i stedet for at vente på
            // musikappen – ellers når armen at glide den forkerte vej et øjeblik, før svaret kommer.
            animator!.scrubbing = true
            intent = nil
            if var input = animator!.input {
                if h.moved, input.duration > 0 { input.position = progress * input.duration }
                else { input.position = animator!.expectedPosition(at: t) ?? input.position }
                input.isPlaying = play
                animator!.update(input, at: t)
                expect(playing: play, position: h.moved && input.duration > 0 ? input.position : nil, until: t + Self.intentWindow)
            }
            // Armen sænkes blødt fra der, hvor den holdes (til rillen, eller til støtten ved pause).
            animator!.dropArm(from: h.angle, lift: holdLift(h, at: t), at: t)
            armDropUntil = t + 1.5                 // musikappens svar bagefter glider også uden ekstra løft
            armHold = nil
            resync(at: t)
            if h.moved {
                onArmSeek?(progress)
                if h.pausedOnPress { onArmClick() }          // spillede den, fortsætter den det nye sted
            } else if !h.pausedOnPress, bounds.contains(local) {
                onArmClick()                                  // klik på armen ved pause: afspil
            }
            Self.setCursor(target(at: local) != nil ? .pointingHand : .arrow)
            return
        }
        guard let pressed, bounds.contains(local), target(at: local) == pressed else { return }
        switch pressed {
        case .arm: onArmClick()
        case .record: onRecordClick()
        case .speed(let s): onSpeedClick(s)
        }
    }

    // MARK: Dæmpning

    private var dimTarget: Double = -1

    func setDim(_ amount: Double) {
        guard amount != dimTarget else { return }
        let first = dimTarget < 0
        dimTarget = amount
        turntable.setDim(amount, animated: !first && window != nil)
    }

    /// Skærmens skala. På fuld skærm (stort dæk) på en almindelig 1x-skærm tegnes billederne i 2x og skaleres pænt ned
    /// (trilineært): plade, etiket og arm drejes hele tiden, og i 1x ville de blive bløde af omsamplingen.
    private var scale: CGFloat {
        // Også i widgetten: armens og pladens fine detaljer bliver ellers til pixelgrød på en 1x-skærm.
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return max(backing, 2)
    }

    func configure(geometry g: TurntableGeometry, style s: TurntableStyle) {
        guard g != geometry || s != style else { return }
        geometry = g
        style = s
        if let a = animator, a.geometry != g { animator = a.with(geometry: g) }
        rebuild()
    }

    private func rebuild() {
        // Intet at tegne før visningen har en størrelse (fx det første øjeblik på fuld skærm).
        guard let geometry, let style, geometry.h >= 1, geometry.size.width >= 1, geometry.size.height >= 1 else { return }
        turntable.configure(geometry, style: style, scale: scale)
        resync()
    }

    /// Hastighed fra indstillingerne. Ændres den mens der spilles, speeder pladen blødt op/ned.
    func setSpeed(_ speed: SpinSpeed) {
        guard let geometry else { return }
        if animator == nil { animator = TurntableAnimator(geometry: geometry) }
        let t = CACurrentMediaTime()
        if animator!.setSpeed(speed, at: t) { resync(at: t) }
    }

    /// Brugeren trækker på fremdriftslinjen: armen glider efter uden at løftes.
    func setScrubbing(_ on: Bool) {
        guard let geometry else { return }
        if animator == nil { animator = TurntableAnimator(geometry: geometry) }
        // Lige efter et slip af armen: spolingen skal også glide (ikke løfte armen igen).
        animator!.scrubbing = on || CACurrentMediaTime() < armDropUntil
    }
    private var armDropUntil: Double = 0

    func update(_ np: NowPlaying?) {
        guard let geometry else { return }
        let t = CACurrentMediaTime()
        if animator == nil { animator = TurntableAnimator(geometry: geometry) }
        let input = np.map { TurntableInput($0, at: .now) }
        if let i = intent {
            if t < i.until, let input, input.trackKey == i.trackKey, i.contradicts(input, at: t) {
                heldBack = np            // vent: musikappen har sikkert bare ikke nået at følge med endnu
                return
            }
            heldBack = nil
        }
        if animator!.update(input, at: t) { resync(at: t) }
    }

    // MARK: Brugerens hensigt
    //
    // Når man griber eller slipper armen, ved animationen straks, hvad der skal ske (pause, spol, afspil). Musikappens
    // svar kommer bagefter, og nogle af dem er forældede: fx "pause" fra trykket, der først lander efter slippet, eller
    // "afspil" med den gamle position, før spolingen er nået frem. De ville sende armen den forkerte vej (mod støtten,
    // eller tilbage og frem igen). Svar, der modsiger det brugeren lige har gjort, holdes derfor tilbage et øjeblik.
    // Kommer der intet nyere, bruges det sidste alligevel bagefter (så er det fx brugeren, der har trykket pause i appen).

    private struct Intent {
        var trackKey: String
        var playing: Bool
        /// Position (s) til tiden `since` efter en spoling, ellers nil.
        var position: Double?
        var since: Double
        var until: Double

        func contradicts(_ input: TurntableInput, at t: Double) -> Bool {
            if input.isPlaying != playing { return true }
            guard let position else { return false }
            let expected = position + (playing ? t - since : 0)
            return abs(input.position - expected) > 1.5      // bekræftelsen må gerne afvige lidt (den glider)
        }
    }
    private var intent: Intent?
    private var heldBack: NowPlaying?
    private var intentWork: DispatchWorkItem?
    /// Så længe ventes der højst på, at musikappen følger med.
    static let intentWindow = 1.0

    private func expect(playing: Bool, position: Double?, until: Double) {
        intentWork?.cancel()
        guard let key = animator?.input?.trackKey else { intent = nil; return }
        let t = CACurrentMediaTime()
        intent = Intent(trackKey: key, playing: playing, position: position, since: t, until: until)
        guard until.isFinite else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.intent = nil
                if let np = self.heldBack { self.heldBack = nil; self.update(np) }
            }
        }
        intentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (until - t), execute: work)
    }

    private func resync(at t: Double = CACurrentMediaTime()) {
        guard let animator else { return }
        if armHold != nil {
            // Armen holdes af brugeren: alt andet kører videre (pladen bremser fx op), armen bliver i hånden.
            // Én transaktion, så der aldrig vises et billede med armen, som animatoren ser den, i stedet for i hånden.
            CATransaction.begin()
            if visible { turntable.sync(animator, at: t) { applyHold() } } else { turntable.applyFinal(animator, at: t); applyHold() }
            CATransaction.commit()
            return
        }
        if visible {
            turntable.sync(animator, at: t)
            if debugFreezeAfterSync { turntable.debugFreezeTransitions() }
            scheduleSettle(after: animator.transitionsEnd(after: t) - t)
        } else {
            turntable.applyFinal(animator, at: t)
        }
    }

    override func layout() {
        super.layout()
        turntable.container.position = .zero
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        if let observedWindow { center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow) }
        observedWindow = window
        guard let window else { return }
        center.addObserver(self, selector: #selector(occlusionChanged),
                           name: NSWindow.didChangeOcclusionStateNotification, object: window)
        // QA M6: læs tilstanden med det samme – vinduet kan allerede være skjult.
        visible = window.occlusionState.contains(.visible) || !window.isVisible
        rebuild()
    }

    /// Skjult vindue (fx andet vindue ovenpå, skærm slukket): fjern animationerne helt. Synlig igen: læg dem ind fra "nu".
    @objc private func occlusionChanged() {
        let nowVisible = window?.occlusionState.contains(.visible) ?? false
        guard nowVisible != visible else { return }
        visible = nowVisible
        if visible { resync() } else if let animator { turntable.applyFinal(animator, at: CACurrentMediaTime()) }
    }
}
