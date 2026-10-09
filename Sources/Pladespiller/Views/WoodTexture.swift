import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Træfoto til tema Træ (CC0-tekstur i `Resources/Textures/`).
///
/// Opslag: 1) `Bundle.main` → `Contents/Resources/Textures/` i den færdige app, 2) `$PLADESPILLER_RESOURCES/Textures/`,
/// 3) `./Resources/Textures/` (så `--render-snapshots` virker fra en worktree). Ingen fil → det tegnede træ (`WoodVeneer`).
/// ImageIO afkoder fotoet i fuld størrelse (højst 2048 px), så fuld skærm ikke skal forstørre et lille udsnit.
enum WoodTexture {
    /// Foretrukne filnavne (uden filtype) – det første der findes bruges; ellers første billede i mappen.
    nonisolated static let preferredNames = ["dark_wood", "walnut", "valnoed", "wood", "trae"]
    nonisolated static let extensions = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp"]
    nonisolated static let maxPixelSize = 2048

    enum State { case notLoaded, loading, ready(CGImage), missing }
    private(set) static var state: State = .notLoaded
    /// Tælles op når fotoet er klar, så kroppens billede i cachen tegnes om (indgår i cache-nøglen).
    private(set) static var generation = 0
    static let didLoad = Notification.Name("PladespillerWoodTextureDidLoad")

    /// QA N8: afkodningen sker i baggrunden. Kaldes tidligt (når pladespilleren oprettes); blokerer aldrig main thread.
    static func prewarm() {
        guard case .notLoaded = state else { return }
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async {
            let img = findFile().flatMap(load)
            let box = UncheckedBox(img)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    state = box.value.map(State.ready) ?? .missing
                    generation += 1
                    NotificationCenter.default.post(name: didLoad, object: nil)
                }
            }
        }
    }

    /// Kun snapshots/test: indlæs med det samme.
    static func loadSynchronously() {
        if case .ready = state { return }
        state = findFile().flatMap(load).map(State.ready) ?? .missing
        generation += 1
    }

    /// Fotoet nedskaleret og drejet så årerne løber vandret. Nil mens det indlæses, eller hvis ingen fil findes.
    static var image: CGImage? {
        if case .ready(let img) = state { return img }
        return nil
    }

    /// Indlæses stadig (så tegnes en neutral træfarve indtil videre i stedet for det tegnede reservetræ).
    static var isPending: Bool {
        switch state {
        case .notLoaded, .loading: true
        default: false
        }
    }

    nonisolated static func findFile() -> URL? {
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

    nonisolated static func load(_ url: URL) -> CGImage? {
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
    nonisolated static func grainRunsVertically(_ img: CGImage) -> Bool {
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

    nonisolated static func rotated90(_ img: CGImage) -> CGImage? {
        let w = img.height, h = img.width
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
    ///
    /// Store flader (fuld skærm): udsnittet gøres større – op til hele fotoet – så det forstørres mindst muligt.
    /// Den forstørrelse der er tilbage laves med Lanczos og en let skarphed, og der lægges fine årer ovenpå
    /// i skærmens egen opløsning, så træet står skarpt tæt på.
    static func fitted(size: CGSize, scale: CGFloat) -> CGImage? {
        guard let src = image else { return nil }
        let iw = CGFloat(src.width), ih = CGFloat(src.height)
        let aspect = size.width / size.height
        let targetW = size.width * scale
        // Hvor stor en del af fotoet: mindst det faste udsnit, mere hvis fladen er bredere end udsnittet i pixels.
        let fraction = min(1, max(cropUnit.width, targetW / iw, targetW / aspect / ih))
        let originX = min(cropUnit.minX, 1 - fraction), originY = min(cropUnit.minY, 1 - fraction)
        var crop = CGRect(x: originX * iw, y: originY * ih, width: fraction * iw, height: fraction * ih)
        // samme forhold som kroppen, skåret fra udsnittets øverste venstre del
        if crop.width / crop.height > aspect { crop.size.width = crop.height * aspect }
        else { crop.size.height = crop.width / aspect }
        guard var piece = src.cropping(to: crop.integral) else { return nil }
        let upscale = targetW / CGFloat(piece.width)
        if upscale > 1.05, let sharp = lanczos(piece, scale: upscale) { piece = sharp }
        let detail = upscale > 1.05
            ? Drawing.noise(size: size, scale: scale, fx: 0.006, fy: 0.55, seed: 33, contrast: 1.6) : nil
        return Drawing.image(size: size, scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: size)
            PlinthRenderer.drawUpright(ctx, piece, in: rect)
            // fine årer (vandrette striber) i fuld opløsning
            Drawing.texture(ctx, CGPath(rect: rect, transform: nil), detail, in: rect, alpha: 0.22)
        }
    }

    /// Skarp forstørrelse (Lanczos) med en let skarphed på lysstyrken.
    static func lanczos(_ img: CGImage, scale: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: img)
        guard let f = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(scale, forKey: kCIInputScaleKey)
        f.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard var out = f.outputImage else { return nil }
        out = out.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.5, kCIInputRadiusKey: 1.5])
        let extent = CGRect(x: 0, y: 0, width: (CGFloat(img.width) * scale).rounded(.down), height: (CGFloat(img.height) * scale).rounded(.down))
        return CIContext(options: [.workingColorSpace: Drawing.colorSpace]).createCGImage(out.cropped(to: extent), from: extent)
    }
}

/// Flytter et CGImage over en tråd-grænse (billedet er uforanderligt).
nonisolated struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
