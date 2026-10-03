// Tegner Pladespillers app-ikon (en pladespiller set ovenfra) i alle størrelser
// og samler dem til Resources/AppIcon.icns med iconutil.
//   swift scripts/make-icon.swift [udmappe]     (standard: Resources)
// Skriver også AppIcon-preview.png (1024 px) i build/ til eftersyn.
import AppKit

let args = CommandLine.arguments
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = args.count > 1 ? URL(fileURLWithPath: args[1]) : root.appendingPathComponent("Resources")

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Tegner ikonet på et 1024×1024-lærred (y opad), skaleret til `px`.
func draw(_ ctx: CGContext, px: Int) {
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Apples ikongitter: flade 824×824 med ~185 pt hjørneradius, centreret.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Skygge under fladen.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(60, 36, 20)); ctx.fillPath()
    ctx.restoreGState()

    // Trækasse: varm gradient + svage årer.
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let wood = CGGradient(colorsSpace: space,
                          colors: [color(176, 112, 62), color(132, 78, 40)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(wood, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    ctx.setStrokeColor(color(90, 50, 22, 0.18))
    ctx.setLineWidth(5)
    for i in 0..<14 {
        let y = 120 + CGFloat(i) * 58
        ctx.move(to: CGPoint(x: 90, y: y))
        ctx.addCurve(to: CGPoint(x: 934, y: y + 18),
                     control1: CGPoint(x: 360, y: y + 26), control2: CGPoint(x: 640, y: y - 22))
    }
    ctx.strokePath()
    // Lys kant foroven.
    ctx.addPath(bodyPath); ctx.setStrokeColor(color(255, 255, 255, 0.22)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()

    // Tallerken + plade.
    let c = CGPoint(x: 462, y: 492)
    func disc(_ r: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0, 0, 0, 0.45))
    disc(318, color(150, 150, 155))
    ctx.restoreGState()
    disc(306, color(22, 22, 24))

    // Riller.
    ctx.setLineWidth(2.2)
    var r: CGFloat = 290
    while r > 128 {
        let a: CGFloat = Int(r) % 3 == 0 ? 0.10 : 0.05
        ctx.setStrokeColor(color(255, 255, 255, a))
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        r -= 9
    }
    // Glans over pladen (to modsatte lyskiler).
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - 306, y: c.y - 306, width: 612, height: 612)); ctx.clip()
    let sheen = CGGradient(colorsSpace: space,
                           colors: [color(255, 255, 255, 0), color(255, 255, 255, 0.16), color(255, 255, 255, 0)] as CFArray,
                           locations: [0, 0.5, 1])!
    for angle in [CGFloat.pi * 0.25, CGFloat.pi * 1.25] {
        ctx.saveGState()
        ctx.move(to: c)
        ctx.addArc(center: c, radius: 320, startAngle: angle - 0.32, endAngle: angle + 0.32, clockwise: false)
        ctx.closePath(); ctx.clip()
        let d = CGPoint(x: cos(angle + .pi / 2) * 320, y: sin(angle + .pi / 2) * 320)
        ctx.drawLinearGradient(sheen, start: CGPoint(x: c.x - d.x, y: c.y - d.y),
                               end: CGPoint(x: c.x + d.x, y: c.y + d.y), options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Etiket.
    disc(118, color(214, 64, 52))
    disc(84, color(232, 96, 70))
    ctx.setStrokeColor(color(255, 236, 210, 0.85)); ctx.setLineWidth(6)
    ctx.strokeEllipse(in: CGRect(x: c.x - 100, y: c.y - 100, width: 200, height: 200))
    disc(16, color(210, 210, 214))
    disc(7, color(120, 120, 126))

    // Tonearm: drejeleje øverst til højre, arm ned over pladen.
    let pivot = CGPoint(x: 800, y: 790)
    let elbow = CGPoint(x: 792, y: 470)
    let head = CGPoint(x: 668, y: 318)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 14, color: color(0, 0, 0, 0.45))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(205, 207, 212)); ctx.setLineWidth(26)
    ctx.move(to: pivot); ctx.addLine(to: elbow); ctx.addLine(to: head); ctx.strokePath()
    // Pickup-hoved.
    ctx.translateBy(x: head.x, y: head.y)
    ctx.rotate(by: atan2(head.y - elbow.y, head.x - elbow.x))
    let shell = CGPath(roundedRect: CGRect(x: -14, y: -32, width: 84, height: 64), cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.addPath(shell); ctx.setFillColor(color(40, 40, 44)); ctx.fillPath()
    ctx.restoreGState()
    ctx.setStrokeColor(color(255, 255, 255, 0.55)); ctx.setLineWidth(6); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: pivot.x - 7, y: pivot.y - 20)); ctx.addLine(to: CGPoint(x: elbow.x - 7, y: elbow.y + 10)); ctx.strokePath()
    // Leje og kontravægt.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: color(0, 0, 0, 0.5))
    ctx.setFillColor(color(170, 172, 178))
    ctx.fillEllipse(in: CGRect(x: pivot.x - 56, y: pivot.y - 56, width: 112, height: 112))
    ctx.restoreGState()
    ctx.setFillColor(color(225, 227, 231))
    ctx.fillEllipse(in: CGRect(x: pivot.x - 34, y: pivot.y - 34, width: 68, height: 68))
    ctx.setFillColor(color(60, 60, 66))
    ctx.fillEllipse(in: CGRect(x: pivot.x - 12, y: pivot.y - 12, width: 24, height: 24))
}

func png(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.imageInterpolation = .high
    let ctx = gc.cgContext
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    draw(ctx, px: px)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("Pladespiller-\(UUID().uuidString)")
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

for base in [16, 32, 128, 256, 512] {
    try png(px: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(px: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
let icns = outDir.appendingPathComponent("AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { FileHandle.standardError.write("iconutil fejlede\n".data(using: .utf8)!); exit(1) }

let previewDir = root.appendingPathComponent("build")
try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
try png(px: 1024).write(to: previewDir.appendingPathComponent("AppIcon-preview.png"))
try png(px: 32).write(to: previewDir.appendingPathComponent("AppIcon-preview-32.png"))
print("Skrevet: \(icns.path)")
