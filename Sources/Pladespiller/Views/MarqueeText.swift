import AppKit
import QuartzCore
import SwiftUI

/// Titel der ruller, hvis den er for lang (brugerens valg). Rulningen kører i Core Animation:
/// teksten tegnes én gang som billede (to kopier med mellemrum), og et uendeligt keyframe-forløb flytter laget
/// – pause ved start, rolig rulning, forfra. Appen laver intet pr. billede. Kun mens der spilles;
/// ved pause står titlen i startpositionen.
struct MarqueeText: View {
    let text: String
    let size: CGFloat
    let width: CGFloat
    let active: Bool
    var weight: NSFont.Weight = .semibold

    @Environment(\.colorScheme) private var scheme
    @Environment(\.textTint) private var tint
    @Environment(\.marqueePhase) private var fixedPhase
    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.displayScale) private var displayScale
    @Environment(\.titleStyle) private var style

    static let gap: CGFloat = 36
    static let speed: Double = 26      // pt/s
    static let hold: Double = 3.0      // pause ved start
    static let fade: CGFloat = 12      // blød kant: til venstre uden for tekstkolonnen, til højre inden for

    private var font: NSFont { .systemFont(ofSize: size, weight: weight) }
    private var swiftFont: Font { .system(size: size, weight: Font.Weight(weight)) }
    /// Fast farve (fx på det flade temas krop) – ellers følger teksten lys/mørk tilstand.
    private func tinted(_ t: Text) -> some View {
        Group { if let tint { t.foregroundStyle(Color(nsColor: tint)) } else { t } }
    }
    private var textWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
    private var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    var body: some View {
        if style == .ellipsis {
            tinted(Text(text).font(swiftFont)).lineLimit(2).truncationMode(.tail)
        } else if textWidth <= width {
            tinted(Text(text).font(swiftFont)).lineLimit(1)
        } else if snapshot != nil || fixedPhase != nil {
            staticMarquee(phase: fixedPhase ?? 0)
        } else {
            MarqueeLayerView(strip: strip, stripWidth: textWidth, height: lineHeight, active: active)
                .frame(width: width + Self.fade, height: lineHeight)
                .padding(.leading, -Self.fade)
                .accessibilityElement()
                .accessibilityLabel(text)
        }
    }

    private var strip: MarqueeStrip {
        MarqueeStrip(text: text, size: size, dark: scheme == .dark, scale: displayScale, weight: weight.rawValue, tint: tint)
    }

    /// Til snapshots: samme billede, forskudt med en fast fase.
    private func staticMarquee(phase: Double) -> some View {
        let distance = textWidth + Self.gap
        return Group {
            if let img = strip.image {
                Image(decorative: img, scale: displayScale)
                    .offset(x: Self.fade - distance * phase)
            }
        }
        .frame(width: width + Self.fade, height: lineHeight, alignment: .leading)
        .clipped()
        .mask(MarqueeMask(fade: Self.fade))
        .padding(.leading, -Self.fade)
    }
}

private struct MarqueeMask: View {
    let fade: CGFloat
    var body: some View {
        GeometryReader { geo in
            let f = fade / max(geo.size.width, 1)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: f),
                                   .init(color: .black, location: 1 - f), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// Tekststrimlen som billede: "titel ··· titel". Caches pr. tekst/størrelse/udseende.
struct MarqueeStrip: Equatable {
    let text: String
    let size: CGFloat
    let dark: Bool
    let scale: CGFloat
    var weight: CGFloat = NSFont.Weight.semibold.rawValue
    var tint: NSColor? = nil

    private static let cache = ImageCache(capacity: 6)

    var image: CGImage? {
        Self.cache.image("\(text)|\(size)|\(dark)|\(scale)|\(weight)|\(tint?.description ?? "-")") {
            let font = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(weight))
            let color = tint ?? (dark ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0, alpha: 0.88))
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let w = ceil((text as NSString).size(withAttributes: attr).width)
            let h = ceil(font.ascender - font.descender + font.leading)
            return Drawing.image(size: CGSize(width: w * 2 + MarqueeText.gap, height: h), scale: scale) { ctx in
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                (text as NSString).draw(at: .zero, withAttributes: attr)
                (text as NSString).draw(at: CGPoint(x: w + MarqueeText.gap, y: 0), withAttributes: attr)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

private struct MarqueeLayerView: NSViewRepresentable {
    let strip: MarqueeStrip
    let stripWidth: CGFloat
    let height: CGFloat
    let active: Bool

    func makeNSView(context: Context) -> MarqueeNSView { MarqueeNSView() }

    func updateNSView(_ view: MarqueeNSView, context: Context) {
        view.update(strip: strip, textWidth: stripWidth, height: height, active: active)
    }
}

final class MarqueeNSView: NSView {
    private let stripLayer = CALayer()
    private let maskLayer = CAGradientLayer()
    private var current: (MarqueeStrip, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(stripLayer)
        stripLayer.anchorPoint = .zero
        stripLayer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        maskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        maskLayer.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Til test.
    var debugAnimationKeys: [String] { stripLayer.animationKeys() ?? [] }

    private var textWidth: CGFloat = 0

    func update(strip: MarqueeStrip, textWidth: CGFloat, height: CGFloat, active: Bool) {
        if let current, current.0 == strip, current.1 == active, self.textWidth == textWidth { return }
        current = (strip, active)
        self.textWidth = textWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let img = strip.image
        stripLayer.contents = img
        stripLayer.contentsScale = strip.scale
        stripLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(img?.width ?? 0) / strip.scale, height: height)
        layoutLayers()
        stripLayer.removeAnimation(forKey: "marquee")
        if active {
            let distance = Double(textWidth + MarqueeText.gap)
            let scroll = distance / MarqueeText.speed
            let cycle = MarqueeText.hold + scroll
            let x0 = Double(MarqueeText.fade)
            let anim = CAKeyframeAnimation(keyPath: "position.x")
            anim.values = [x0, x0, x0 - distance]
            anim.keyTimes = [0, NSNumber(value: MarqueeText.hold / cycle), 1]
            anim.duration = cycle
            anim.repeatCount = .infinity
            anim.calculationMode = .linear
            anim.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            anim.beginTime = 0   // "nu" ved commit (QA N2: ingen absolutte tider)
            stripLayer.add(anim, forKey: "marquee")
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutLayers()
        CATransaction.commit()
    }

    private func layoutLayers() {
        stripLayer.position = CGPoint(x: MarqueeText.fade, y: (bounds.height - stripLayer.bounds.height) / 2)
        maskLayer.frame = bounds
        let f = Double(MarqueeText.fade / max(bounds.width, 1))
        maskLayer.locations = [0, NSNumber(value: f), NSNumber(value: 1 - f), 1]
    }
}


extension Font.Weight {
    init(_ w: NSFont.Weight) {
        switch w {
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .medium: self = .medium
        case .regular: self = .regular
        default: self = .semibold
        }
    }
}
