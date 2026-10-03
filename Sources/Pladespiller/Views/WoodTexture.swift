import CoreGraphics
import Foundation
import ImageIO

/// Træfoto til tema Træ (CC0-tekstur i `Resources/Textures/`).
///
/// Opslag: 1) `Bundle.main` → `Contents/Resources/Textures/` i den færdige app, 2) `$PLADESPILLER_RESOURCES/Textures/`,
/// 3) `./Resources/Textures/` (så `--render-snapshots` virker fra en worktree). Ingen fil → det tegnede træ (`WoodVeneer`).
/// Originalen læses aldrig ind i fuld størrelse: ImageIO laver et thumbnail på højst 1024 px, som caches.
enum WoodTexture {
    /// Foretrukne filnavne (uden filtype) – det første der findes bruges; ellers første billede i mappen.
    static var preferredNames = ["dark_wood", "walnut", "valnoed", "wood", "trae"]
    static let extensions = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp"]
    static let maxPixelSize = 1400

    private static var loaded = false
    private static var cached: CGImage?

    /// Fotoet nedskaleret og drejet så årerne løber vandret (på langs af kroppen). Nil hvis ingen fil findes.
    static var image: CGImage? {
        if !loaded {
            loaded = true
            if let url = findFile() { cached = load(url) }
        }
        return cached
    }

    static func findFile() -> URL? {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Textures")) }
        if let env = ProcessInfo.processInfo.environment["PLADESPILLER_RESOURCES"] {
            let base = URL(fileURLWithPath: env)
            dirs.append(base.appendingPathComponent("Textures"))
            dirs.append(base)
        }
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Textures"))

        for name in preferredNames {
            for ext in extensions {
                if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Textures") { return u }
            }
        }
        let fm = FileManager.default
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let images = files.filter { extensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for name in preferredNames {
                if let hit = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(name) }) { return hit }
            }
            if let first = images.first { return first }
        }
        return nil
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return grainRunsVertically(thumb) ? rotated90(thumb) : thumb
    }

    /// Årer giver stor variation på tværs af åren og lille langs den. Måles på en lille gråtonekopi.
    static func grainRunsVertically(_ img: CGImage) -> Bool {
        let n = 96
        var px = [UInt8](repeating: 0, count: n * n)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return false }
        var gx = 0, gy = 0
        for y in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let p = Int(px[y * n + x])
                gx += abs(Int(px[y * n + x + 1]) - p)
                gy += abs(Int(px[(y + 1) * n + x]) - p)
            }
        }
        return gx > gy   // stor vandret variation → årerne går lodret
    }

    static func rotated90(_ img: CGImage) -> CGImage? {
        let w = img.height, h = img.width
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Drawing.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage() ?? img
    }

    /// Fast udsnit af fotoet (enhedskoordinater, y nedad) – samme hver gang, så widgetten ser ens ud fra start til start.
    /// Et udsnit på ca. 3/4 af fotoet giver passende grove årer på kroppen.
    static let cropUnit = CGRect(x: 0.10, y: 0.14, width: 0.74, height: 0.74)

    /// Fotoet beskåret (aspect fill inden for udsnittet) og skaleret til kroppens størrelse. Kaldes kun via billedcachen.
    static func fitted(size: CGSize, scale: CGFloat) -> CGImage? {
        guard let src = image else { return nil }
        let iw = CGFloat(src.width), ih = CGFloat(src.height)
        var crop = CGRect(x: cropUnit.minX * iw, y: cropUnit.minY * ih, width: cropUnit.width * iw, height: cropUnit.height * ih)
        // samme forhold som kroppen, skåret fra udsnittets øverste venstre del
        let aspect = size.width / size.height
        if crop.width / crop.height > aspect { crop.size.width = crop.height * aspect }
        else { crop.size.height = crop.width / aspect }
        guard let piece = src.cropping(to: crop.integral) else { return nil }
        return Drawing.image(size: size, scale: scale) { ctx in
            PlinthRenderer.drawUpright(ctx, piece, in: CGRect(origin: .zero, size: size))
        }
    }
}
