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

    /// Kun test (LiveSequenceTest): efterlign QA-fejlen N2.
    var debugFreezeAfterSync = false

    /// Sikkerhedsnet (QA N2): sæt sluttilstanden når overgangene er færdige. Én planlagt opgave ad gangen.
    private var settleWork: DispatchWorkItem?
    private func scheduleSettle(after delay: Double) {
        settleWork?.cancel()
        guard delay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let animator = self.animator, self.visible else { return }
                self.turntable.settle(animator, at: CACurrentMediaTime())
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.15, execute: work)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func updateCursor(_ event: NSEvent) {
        if armDrag?.active == true { NSCursor.closedHand.set(); return }
        let over = target(at: convert(event.locationInWindow, from: nil)) != nil
        (over ? NSCursor.pointingHand : NSCursor.arrow).set()
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
        let a = turntable.visibleArmAngle()
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
        armDrag = nil
        if pressed == .arm, onArmSeek != nil, let g = geometry {
            // Armen kan trækkes: hold fast i det sted på armen, man tog fat (vinklen mellem musen og armen).
            let a = turntable.visibleArmAngle()
            armDrag = ArmDrag(start: local, grab: Self.wrap(mouseAngle(local, g) - a), angle: a)
            dragClaim?.isClaimed = true          // et træk i armen flytter ikke widgetten
        }
    }

    // MARK: Træk i armen = spol
    //
    // Som på en rigtig pladespiller: armen løftes, følger musen hen over pladen og sænkes, hvor man slipper.
    // Der spoles først ved slip (ikke undervejs), så musikken ikke hakker.

    private struct ArmDrag {
        var start: NSPoint
        var grab: Double
        var angle: Double
        var active = false
    }
    private var armDrag: ArmDrag?
    private static let armDragLift = 0.7

    private func mouseAngle(_ local: NSPoint, _ g: TurntableGeometry) -> Double {
        let p = CGPoint(x: local.x, y: bounds.height - local.y)          // y nedad som geometrien
        return Double(atan2(p.y - g.pivot.y, p.x - g.pivot.x))
    }

    private static func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    /// Armvinklen for musen, klemt til rillerne (yderste … inderste), og fremdriften der hører til.
    private func armPosition(_ local: NSPoint, _ drag: ArmDrag, _ g: TurntableGeometry) -> (angle: Double, progress: Double) {
        let raw = drag.angle + Self.wrap(mouseAngle(local, g) - drag.grab - drag.angle)
        let f = g.progress(forArmAngle: CGFloat(raw))
        return (Double(g.armAngle(forProgress: f)), f)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = armDrag, let g = geometry else { return }
        let local = convert(event.locationInWindow, from: nil)
        if !drag.active {
            guard hypot(local.x - drag.start.x, local.y - drag.start.y) > 3 else { return }
            drag.active = true
            NSCursor.closedHand.set()
        }
        drag.angle = armPosition(local, drag, g).angle
        armDrag = drag
        turntable.setManualArm(angle: drag.angle, lift: Self.armDragLift)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; armDrag = nil; dragClaim?.isClaimed = false }
        let local = convert(event.locationInWindow, from: nil)
        if let drag = armDrag, drag.active, let g = geometry, animator != nil {
            let (angle, f) = armPosition(local, drag, g)
            let t = CACurrentMediaTime()
            animator!.dropArm(from: angle, lift: Self.armDragLift, at: t)
            armDropUntil = t + 1.5
            animator!.scrubbing = true            // næste opdatering (den nye position) glider uden ekstra løft
            resync(at: t)
            onArmSeek?(f)
            (target(at: local) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
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
        if animator!.update(input, at: t) { resync(at: t) }
    }

    private func resync(at t: Double = CACurrentMediaTime()) {
        guard let animator else { return }
        if let drag = armDrag, drag.active {
            // Armen holdes af brugeren: alt andet kører videre, armen bliver under musen.
            if visible { turntable.sync(animator, at: t) } else { turntable.applyFinal(animator, at: t) }
            turntable.setManualArm(angle: drag.angle, lift: Self.armDragLift)
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
