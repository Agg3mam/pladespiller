import AppKit
import QuartzCore
import SwiftUI

/// I snapshots: tegn pladespilleren i denne pose i stedet for den levende CA-visning.
struct TurntableSnapshotPose {
    var pose: TurntablePose
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
    let theme: TurntableTheme
    let nowPlaying: NowPlaying?

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.displayScale) private var displayScale

    var geometry: TurntableGeometry { TurntableGeometry(size: size, cornerRadius: cornerRadius) }
    var style: TurntableStyle { TurntableStyle.make(theme: theme, artwork: nowPlaying?.artwork) }

    var body: some View {
        Group {
            if let snapshot {
                if let cg = TurntableLayer.snapshot(geometry, style: style, scale: displayScale, pose: snapshot.pose) {
                    Image(decorative: cg, scale: displayScale)
                        .resizable()
                }
            } else {
                LiveTurntable(geometry: geometry, style: style, nowPlaying: nowPlaying)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let np = nowPlaying else { return "Pladespiller. Intet spiller" }
        return "Pladespiller. \(np.isPlaying ? "Spiller" : "Pause"): \(np.title) af \(np.artist)"
    }
}

private struct LiveTurntable: NSViewRepresentable {
    let geometry: TurntableGeometry
    let style: TurntableStyle
    let nowPlaying: NowPlaying?

    func makeNSView(context: Context) -> TurntableNSView { TurntableNSView() }

    func updateNSView(_ view: TurntableNSView, context: Context) {
        view.configure(geometry: geometry, style: style)
        view.update(nowPlaying)
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
        layer?.addSublayer(turntable.root)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Klik og træk går videre til widgetten (vindue/menu ejes af Vindue-agenten).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    func configure(geometry g: TurntableGeometry, style s: TurntableStyle) {
        guard g != geometry || s != style else { return }
        geometry = g
        style = s
        if let a = animator, a.geometry != g { animator = a.with(geometry: g) }
        rebuild()
    }

    private func rebuild() {
        guard let geometry, let style else { return }
        turntable.configure(geometry, style: style, scale: scale)
        resync()
    }

    func update(_ np: NowPlaying?) {
        guard let geometry else { return }
        let t = CACurrentMediaTime()
        if animator == nil { animator = TurntableAnimator(geometry: geometry) }
        let input = np.map { TurntableInput($0, at: .now) }
        if animator!.update(input, at: t) { resync(at: t) }
    }

    private func resync(at t: Double = CACurrentMediaTime()) {
        guard let animator else { return }
        if visible { turntable.sync(animator, at: t) } else { turntable.apply(animator.pose(at: t)) }
    }

    override func layout() {
        super.layout()
        turntable.root.position = .zero
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
        rebuild()
    }

    /// Skjult vindue (fx andet vindue ovenpå, skærm slukket): fjern animationerne helt. Synlig igen: læg dem ind fra "nu".
    @objc private func occlusionChanged() {
        let nowVisible = window?.occlusionState.contains(.visible) ?? false
        guard nowVisible != visible else { return }
        visible = nowVisible
        if visible { resync() } else { turntable.stopAnimations() }
    }
}
