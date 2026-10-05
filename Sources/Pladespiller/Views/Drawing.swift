import AppKit
import CoreGraphics
import CoreImage

/// Små tegnehjælpere. Alle billeder tegnes med y nedad (som SwiftUI), i punkter, ganget med `scale`.
enum Drawing {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Tegner et billede på `size` punkter ved `scale`. Konteksten er vendt, så (0,0) er øverst til venstre, enhed = punkt.
    static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    /// Pixel-for-pixel tegning (RGBA, præmultipliceret). `shade(x, y)` får punktkoordinater (y nedad) for pixlens midte.
    static func pixels(size: CGSize, scale: CGFloat,
                       _ shade: (_ x: Float, _ y: Float) -> SIMD4<Float>) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let inv = Float(1 / scale)
        buf.withUnsafeMutableBufferPointer { p in
            for py in 0..<h {
                let y = (Float(py) + 0.5) * inv
                for px in 0..<w {
                    let x = (Float(px) + 0.5) * inv
                    var c = shade(x, y)
                    c = c.clamped(lowerBound: SIMD4(repeating: 0), upperBound: SIMD4(repeating: 1))
                    let i = (py * w + px) * 4
                    p[i] = UInt8(c.x * 255 + 0.5)
                    p[i + 1] = UInt8(c.y * 255 + 0.5)
                    p[i + 2] = UInt8(c.z * 255 + 0.5)
                    p[i + 3] = UInt8(c.w * 255 + 0.5)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(buf) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Gaussisk sløring (bruges én gang pr. størrelse til skygger).
    static func blurred(_ image: CGImage, radiusPx: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: radiusPx).cropped(to: ci.extent)
        return CIContext(options: [.workingColorSpace: colorSpace]).createCGImage(out, from: ci.extent)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
    }

    static func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { color(w, w, w, a) }

    static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: colorSpace, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
    }

    /// Fylder en sti med lineær gradient.
    static func fill(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from a: CGPoint, to b: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Tegner en streg (af `path`) med lineær gradient.
    static func stroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat, _ g: CGGradient, from a: CGPoint, to b: CGPoint) {
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
        fill(ctx, stroked, g, from: a, to: b)
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
    }

    /// NSImage → CGImage.
    static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Gennemsnitsfarve af et billede (til tema "Auto").
    static func averageColor(_ image: CGImage) -> SIMD3<Float> {
        // Bufferen skal leve hele tiden konteksten bruges (QA M3): alt sker inde i withUnsafeMutableBytes.
        var px = [UInt8](repeating: 0, count: 4)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return SIMD3(0.4, 0.4, 0.4) }
        return SIMD3(Float(px[0]), Float(px[1]), Float(px[2])) / 255
    }

    /// Coverets fremherskende farve: farverne i et lille udsnit grupperes efter nuance; den gruppe der fylder mest
    /// (vægtet med mætning, så små farvestænk ikke vinder over store flader, og grå ikke dominerer) vinder.
    static func dominantColor(_ image: CGImage) -> SIMD3<Float> {
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return SIMD3(0.5, 0.5, 0.5) }
        let bins = 12
        var weight = [Float](repeating: 0, count: bins + 1)       // sidste spand = grå
        var sum = [SIMD3<Float>](repeating: .zero, count: bins + 1)
        for i in 0..<(n * n) {
            let c = SIMD3(Float(px[i * 4]), Float(px[i * 4 + 1]), Float(px[i * 4 + 2])) / 255
            let mx = max(c.x, c.y, c.z), mn = min(c.x, c.y, c.z)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            var hue: Float = 0
            if mx > mn {
                if mx == c.x { hue = (c.y - c.z) / (mx - mn) }
                else if mx == c.y { hue = 2 + (c.z - c.x) / (mx - mn) }
                else { hue = 4 + (c.x - c.y) / (mx - mn) }
                hue = (hue / 6).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
            }
            let bin = sat < 0.18 || mx < 0.15 ? bins : min(bins - 1, Int(hue * Float(bins)))
            let w: Float = bin == bins ? 0.35 : (0.3 + sat) * (0.4 + mx)
            weight[bin] += w
            sum[bin] += c * w
        }
        let best = weight.indices.max { weight[$0] < weight[$1] } ?? bins
        return weight[best] > 0 ? sum[best] / weight[best] : SIMD3(0.5, 0.5, 0.5)
    }

    /// Gråtonekopi (til dæmpet look: tones ind over originalen i stedet for et CI-filter pr. billede).
    static func grayscale(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.saturation)
        ctx.setFillColor(gray(0.5))
        ctx.clip(to: rect, mask: image)
        ctx.fill(rect)
        return ctx.makeImage()
    }
}

/// Deterministisk værdistøj (så teksturer ser ens ud hver gang).
struct ValueNoise {
    let seed: UInt32

    @inline(__always) func hash(_ x: Int32, _ y: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }

    @inline(__always) func value(_ x: Float, _ y: Float) -> Float {
        let xf0 = x.rounded(.down), yf0 = y.rounded(.down)
        let xi = Int32(truncatingIfNeeded: Int(xf0)), yi = Int32(truncatingIfNeeded: Int(yf0))
        let fx = x - xf0, fy = y - yf0
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi), b = hash(xi &+ 1, yi), c = hash(xi, yi &+ 1), d = hash(xi &+ 1, yi &+ 1)
        return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
    }

    /// Fraktal støj 0...1.
    func fbm(_ x: Float, _ y: Float, octaves: Int = 3) -> Float {
        var sum: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += value(x * f, y * f) * amp
            norm += amp
            amp *= 0.5
            f *= 2.03
        }
        return sum / norm
    }
}

@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

@inline(__always) func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
