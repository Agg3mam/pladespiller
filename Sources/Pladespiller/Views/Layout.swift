import AppKit
import QuartzCore
import SwiftUI

/// Fast layoutgitter for widgetten (Apples widget-designsprog). Alle mål i punkter.
///
/// - Indhold (tekst, knapper) har `padding` = 16 til widgettens kant.
/// - Pladespillerens krop er et "objekt" med `objectInset` = 8 til kanten og koncentriske hjørner (28 − 8 = 20).
///   Dermed ligger tekstens overkant og knappernes underkant præcis `objectInset` inde i forhold til kroppens kanter.
/// - `gap` = 12 mellem kroppen og tekstkolonnen.
/// - Knapikonerne er beskåret til deres synlige blæk (`Glyph`), så deres visuelle kant er rammens kant.
enum Layout {
    static let padding: CGFloat = 16
    static let objectInset: CGFloat = 8
    static let gap: CGFloat = 12
    static var objectRadius: CGFloat { WidgetMetrics.cornerRadius - objectInset }

    // Typografi (ens i alle størrelser)
    static let titleSize: CGFloat = 15
    static let secondarySize: CGFloat = 13
    static let tertiarySize: CGFloat = 12
    static let timeSize: CGFloat = 11
    static let lineGap: CGFloat = 2          // mellem titel og kunstner/album

    // Knapper
    static let playDiameter: CGFloat = 32
    static let skipGlyphHeight: CGFloat = 12
    static let playGlyphHeight: CGFloat = 14
    static let sourceIconSize: CGFloat = 14

    // Fremdrift
    static let progressHeight: CGFloat = 3
    static let progressToButtons: CGFloat = 10

    static func titleFont() -> NSFont { .systemFont(ofSize: titleSize, weight: .semibold) }

    /// Sidste tegns højre side bearing (luft efter blækket).
    static func trailingBearing(_ text: String, font: NSFont) -> CGFloat {
        guard let last = text.last else { return 0 }
        let ct = font as CTFont
        var chars = Array(String(last).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ct, &chars, &glyphs, chars.count), var glyph = glyphs.first else { return 0 }
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(ct, .horizontal, &glyph, &rect, 1)
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyph, &adv, 1)
        return max(0, adv.width - rect.maxX).rounded(toPlaces: 2)
    }

    static func timeFont() -> NSFont { .monospacedDigitSystemFont(ofSize: timeSize, weight: .medium) }

    /// Første bogstavs venstre "side bearing" (luften før blækket). Titlen flyttes så meget til venstre,
    /// så dens synlige venstrekant flugter med ikonerne – uanset hvilket bogstav titlen starter med.
    static func leadingBearing(_ text: String, font: NSFont) -> CGFloat {
        guard let first = text.first else { return 0 }
        let ct = font as CTFont
        var chars = Array(String(first).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ct, &chars, &glyphs, chars.count), let g = glyphs.first else { return 0 }
        var glyph = g
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(ct, .horizontal, &glyph, &rect, 1)
        return max(0, rect.minX).rounded(toPlaces: 2)
    }

    /// Hvor meget en tekstlinjes ramme rager op over versalhøjden (så versalhøjden kan placeres præcist).
    static func capInset(_ font: NSFont) -> CGFloat {
        let lineTop = font.ascender          // SwiftUI-tekstens ramme starter ved ascender (målt i layout-tjek)
        return (lineTop - font.capHeight).rounded(toPlaces: 2)
    }
}

extension CGFloat {
    func rounded(toPlaces p: Int) -> CGFloat {
        let m = pow(10, CGFloat(p))
        return (self * m).rounded() / m
    }
}

// MARK: - SF Symbols beskåret til synligt blæk

/// SF Symbols har indre luft omkring tegnet. Her tegnes symbolet og beskæres til de pixels der faktisk er farvet,
/// så venstrekanten af det første ikon kan flugte præcist med tekstens venstrekant.
enum Glyph {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, height: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage? {
        let key = "\(name)|\(height)|\(weight.rawValue)"
        if let hit = cache[key] { return hit }
        // Tegn stort, find blækket, skalér til ønsket højde.
        let big: CGFloat = 96
        guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: big, weight: weight)) else { return nil }
        let pw = Int(sym.size.width * 2) + 8, ph = Int(sym.size.height * 2) + 8
        var px = [UInt8](repeating: 0, count: pw * ph * 4)
        let ink: CGRect? = px.withUnsafeMutableBytes { raw -> CGRect? in
            guard let ctx = CGContext(data: raw.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            sym.draw(in: NSRect(x: 4, y: 4, width: sym.size.width * 2, height: sym.size.height * 2))
            NSGraphicsContext.restoreGraphicsState()
            let p = raw.bindMemory(to: UInt8.self)
            var minX = pw, minY = ph, maxX = -1, maxY = -1
            for y in 0..<ph { for x in 0..<pw where p[(y * pw + x) * 4 + 3] > 24 {
                minX = Swift.min(minX, x); maxX = Swift.max(maxX, x); minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
            } }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        guard let ink, let provider = CGDataProvider(data: Data(px) as CFData),
              let full = CGImage(width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pw * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let cropped = full.cropping(to: ink) else { return nil }
        let k = height / ink.height
        let img = NSImage(cgImage: cropped, size: NSSize(width: (ink.width * k).rounded(toPlaces: 2), height: height))
        img.isTemplate = true
        cache[key] = img
        return img
    }
}

/// Et beskåret symbol som SwiftUI-view (farves med foregroundStyle).
struct GlyphView: View {
    let name: String
    let height: CGFloat
    var body: some View {
        if let img = Glyph.image(name, height: height) {
            Image(nsImage: img).renderingMode(.template).resizable().frame(width: img.size.width, height: img.size.height)
        }
    }
}

// MARK: - Fremdrift

/// Tynd fremdriftslinje. Live kører den i Core Animation (bredden animeres lineært til sangens slutning,
/// så appen laver intet pr. billede). I snapshots tegnes den statisk i SwiftUI.
struct ProgressLine: View {
    let np: NowPlaying

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme
    @Environment(\.windowIsVisible) private var windowVisible

    private var dark: Bool { scheme == .dark }

    var body: some View {
        if snapshot != nil {
            GeometryReader { geo in
                let f = np.progress(at: np.positionTimestamp)
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    if np.duration > 0 {
                        Capsule().fill(fillColor).frame(width: max(Layout.progressHeight, geo.size.width * f))
                    }
                }
            }
            .frame(height: Layout.progressHeight)
        } else {
            ProgressLayerView(np: np, active: np.isPlaying && windowVisible,
                              track: NSColor(white: dark ? 1 : 0, alpha: dark ? 0.22 : 0.14),
                              fill: NSColor(white: dark ? 1 : 0, alpha: dark ? 0.88 : 0.78))
                .frame(height: Layout.progressHeight)
        }
    }

    private var trackColor: Color { Color(white: dark ? 1 : 0).opacity(dark ? 0.22 : 0.14) }
    private var fillColor: Color { Color(white: dark ? 1 : 0).opacity(dark ? 0.88 : 0.78) }
}

private struct ProgressLayerView: NSViewRepresentable {
    let np: NowPlaying
    let active: Bool
    let track: NSColor
    let fill: NSColor

    func makeNSView(context: Context) -> ProgressNSView { ProgressNSView() }
    func updateNSView(_ v: ProgressNSView, context: Context) {
        v.update(position: np.position(at: .now), duration: np.duration, active: active, track: track, fill: fill)
    }
}

final class ProgressNSView: NSView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var state: (Double, Double, Bool, NSColor, NSColor, CGFloat)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [trackLayer, fillLayer] {
            l.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            l.anchorPoint = .zero
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var startPosition = 0.0, duration = 0.0, active = false

    func update(position: Double, duration: Double, active: Bool, track: NSColor, fill: NSColor) {
        // Små afvigelser i positionen (< 1 s) ignoreres, så linjen ikke starter forfra ved hver opdatering.
        if let s = state, s.1 == duration, s.2 == active, s.3 == track, s.4 == fill, s.5 == bounds.width,
           abs((s.0 + (active ? CACurrentMediaTime() - startTime : 0)) - position) < 1 { return }
        state = (position, duration, active, track, fill, bounds.width)
        startTime = CACurrentMediaTime()
        startPosition = position
        self.duration = duration
        self.active = active
        apply(track: track, fill: fill)
    }

    private var startTime = 0.0

    override func layout() {
        super.layout()
        if let s = state { state = nil; update(position: s.0 + (s.2 ? CACurrentMediaTime() - startTime : 0), duration: s.1, active: s.2, track: s.3, fill: s.4) }
    }

    private func apply(track: NSColor, fill: NSColor) {
        let w = bounds.width, h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.cornerRadius = h / 2
        trackLayer.backgroundColor = track.cgColor
        fillLayer.cornerRadius = h / 2
        fillLayer.backgroundColor = fill.cgColor
        fillLayer.removeAllAnimations()
        let f = duration > 0 ? min(max(startPosition / duration, 0), 1) : 0
        let w0 = duration > 0 ? max(h, w * f) : 0     // radio uden varighed: kun sporet, ingen fyld
        fillLayer.bounds = CGRect(x: 0, y: 0, width: active && duration > 0 ? w : w0, height: h)
        fillLayer.position = .zero
        if active, duration > 0, w0 < w {
            let anim = CABasicAnimation(keyPath: "bounds.size.width")
            anim.fromValue = w0
            anim.toValue = w
            anim.duration = max(0.1, duration - startPosition)
            anim.beginTime = 0
            // Linjen bevæger sig langsomt: lav billedrate er nok.
            anim.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 30, preferred: 15)
            fillLayer.add(anim, forKey: "progress")
        }
        CATransaction.commit()
    }
}

/// Fremdriftslinje med forløbet tid til venstre og varighed til højre, på én linje.
struct ProgressRow: View {
    let np: NowPlaying
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 8) {
            TimeLabel(np: np, mode: .elapsed).probe("tid-start")
            SeekBar(np: np, onSeek: onSeek).probe("fremdrift")
            TimeLabel(np: np, mode: .total).probe("tid-slut")
        }
    }
}

/// Tid som tekst. Forløbet tid opdateres én gang i sekundet og kun mens der spilles og vinduet er synligt.
struct TimeLabel: View {
    enum Mode { case elapsed, total }
    let np: NowPlaying
    let mode: Mode

    @Environment(\.turntableSnapshot) private var snapshot
    @Environment(\.windowIsVisible) private var windowVisible
    @Environment(\.seekPreview) private var preview

    var body: some View {
        // Under træk på linjen følger tiden musen.
        if mode == .elapsed, let f = preview?.fraction ?? ScrubState.shared.fraction(for: np) {
            label(f * np.duration)
        } else if mode == .elapsed, np.isPlaying, snapshot == nil, windowVisible {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in label(np.position(at: ctx.date)) }
        } else {
            label(mode == .total ? np.duration : np.position(at: snapshot == nil ? .now : np.positionTimestamp))
        }
    }

    private func label(_ seconds: Double) -> some View {
        Text(mode == .total && np.duration <= 0 ? "–:––" : formatTime(seconds))
            .font(Font(Layout.timeFont() as CTFont))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Måling af layout (kun snapshots)

private struct LayoutProbeKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Kun layout-tjek: kun elementet med dette navn tegnes (alt andet usynligt), så dets synlige kanter kan måles.
    var layoutProbe: String? {
        get { self[LayoutProbeKey.self] }
        set { self[LayoutProbeKey.self] = newValue }
    }
}

private struct ProbeModifier: ViewModifier {
    let name: String
    @Environment(\.layoutProbe) private var probe
    func body(content: Content) -> some View {
        content
            .opacity(probe == nil || probe == name ? 1 : 0)
            // "navn#ramme": tegn elementets ramme som en flade (måler den typografiske ramme i stedet for blækket)
            .overlay { if probe == name + "#ramme" { Rectangle().fill(Color.black) } }
    }
}

extension View {
    /// Markerer et element til layout-tjekket.
    func probe(_ name: String) -> some View { modifier(ProbeModifier(name: name)) }
}
