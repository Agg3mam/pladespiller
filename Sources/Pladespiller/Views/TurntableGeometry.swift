import CoreGraphics
import Foundation

/// Pladespillerens mål i punkter, y nedad, (0,0) = kroppens øverste venstre hjørne.
/// Alt er proportionalt med kroppens højde `h`; ekstra bredde lægges ligeligt i begge sider.
/// Vinkler er i radianer, med uret (y nedad), 0 = mod højre.
struct TurntableGeometry: Hashable {
    let size: CGSize
    let cornerRadius: CGFloat

    init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var h: CGFloat { size.height }
    /// Vandret forskydning når kroppen er bredere end høj.
    var ox: CGFloat { max(0, (size.width - size.height * 0.98) / 2) }

    // Tallerken og plade
    var center: CGPoint { CGPoint(x: ox + h * 0.43, y: h * 0.52) }
    var platterRadius: CGFloat { h * 0.385 }
    var recordRadius: CGFloat { h * 0.370 }
    var grooveOuterRadius: CGFloat { h * 0.355 }
    var grooveInnerRadius: CGFloat { h * 0.178 }
    var labelRadius: CGFloat { h * 0.145 }
    var spindleRadius: CGFloat { h * 0.0105 }
    var holeRadius: CGFloat { h * 0.017 }

    // Pickuparm (lokale koordinater: omdrejningspunkt i (0,0), armen langs +x, +y = mod pladen i hvile)
    var pivot: CGPoint { CGPoint(x: ox + h * 0.845, y: h * 0.19) }
    var tubeLength: CGFloat { h * 0.47 }
    var tubeWidth: CGFloat { max(2, h * 0.021) }
    var headshellLength: CGFloat { h * 0.088 }
    var headshellWidth: CGFloat { h * 0.044 }
    var headshellAngle: CGFloat { 24 * .pi / 180 }
    var counterweightStart: CGFloat { -h * 0.062 }
    var counterweightEnd: CGFloat { -h * 0.125 }
    var counterweightRadius: CGFloat { h * 0.031 }
    var basePlateRadius: CGFloat { h * 0.068 }

    /// Pickupnålens position i armens lokale koordinater.
    var stylusLocal: CGPoint {
        CGPoint(x: tubeLength + headshellLength * 0.82 * cos(headshellAngle),
                y: headshellLength * 0.82 * sin(headshellAngle))
    }
    var effectiveLength: CGFloat { hypot(stylusLocal.x, stylusLocal.y) }
    var stylusOffsetAngle: CGFloat { atan2(stylusLocal.y, stylusLocal.x) }

    /// Armens hvilevinkel (røret peger næsten lige ned).
    var restAngle: CGFloat { 92 * .pi / 180 }
    /// Hvor armstøtten står (lokalt x langs røret i hvile).
    var armRestLocalX: CGFloat { tubeLength * 0.74 }

    func stylus(atArmAngle a: CGFloat) -> CGPoint {
        let L = effectiveLength, d = a + stylusOffsetAngle
        return CGPoint(x: pivot.x + L * cos(d), y: pivot.y + L * sin(d))
    }

    func world(_ local: CGPoint, armAngle a: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + local.x * cos(a) - local.y * sin(a),
                y: pivot.y + local.x * sin(a) + local.y * cos(a))
    }

    /// Armvinklen hvor nålen står i afstanden `r` fra centrum (første skæring set fra hvile).
    func armAngle(forRadius r: CGFloat) -> CGFloat {
        func dist(_ a: CGFloat) -> CGFloat {
            let p = stylus(atArmAngle: a)
            return hypot(p.x - center.x, p.y - center.y)
        }
        // Afstanden falder monotont fra hvile indtil nærmeste punkt.
        var lo = restAngle, hi = restAngle + 1.2
        // find nærmeste punkt (minimum) groft
        var best = hi, bestD = CGFloat.greatestFiniteMagnitude
        var a = lo
        while a <= hi {
            let d = dist(a)
            if d < bestD { bestD = d; best = a }
            a += 0.005
        }
        hi = best
        if dist(lo) < r { return lo }
        if bestD > r { return hi }
        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            if dist(mid) > r { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Armvinkel for fremdrift 0 (yderste rille) ... 1 (inderste rille).
    func armAngle(forProgress p: Double) -> CGFloat {
        let table = progressTable
        let x = min(max(p, 0), 1) * Double(table.count - 1)
        let i = min(Int(x), table.count - 2)
        let f = CGFloat(x - Double(i))
        return table[i] + (table[i + 1] - table[i]) * f
    }

    private var progressTable: [CGFloat] {
        if let t = Self.tables[self] { return t }
        let t = (0...64).map { i -> CGFloat in
            let p = CGFloat(i) / 64
            return armAngle(forRadius: grooveOuterRadius - (grooveOuterRadius - grooveInnerRadius) * p)
        }
        Self.tables[self] = t
        return t
    }

    private static var tables: [TurntableGeometry: [CGFloat]] = [:]

    // Små detaljer på kroppen
    var ledCenter: CGPoint { CGPoint(x: size.width - ox - h * 0.075, y: h * 0.915) }
    var ledRadius: CGFloat { max(1.6, h * 0.0115) }
    var speedButtons: [CGPoint] {
        [CGPoint(x: size.width - ox - h * 0.275, y: h * 0.915), CGPoint(x: size.width - ox - h * 0.185, y: h * 0.915)]
    }
    var speedButtonRadius: CGFloat { h * 0.03 }
}
