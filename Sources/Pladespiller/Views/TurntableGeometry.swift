import CoreGraphics
import Foundation

/// Pladespillerens mål i punkter, y nedad, (0,0) = kroppens øverste venstre hjørne.
///
/// Kroppen (`size`) kan være større end selve "dækket" (`deck`): det kvadrat hvor tallerken, arm og knapper ligger.
/// Alt i dækket er proportionalt med dets side `h`. Standard: dækket er kvadratet midt i kroppen.
/// Gitter: alle detaljer holder `margin` (= 7,5 % af h) til dækkets kanter. Pladen er lodret centreret.
/// Vinkler er i radianer, med uret (y nedad), 0 = mod højre.
struct TurntableGeometry: Hashable {
    let size: CGSize
    let cornerRadius: CGFloat
    let deck: CGRect
    /// Flad stil (referencebilledet): større plade uden metalkant, meget stor cover-etiket, enkel hvid arm.
    let flat: Bool

    init(size: CGSize, cornerRadius: CGFloat, deck: CGRect? = nil, flat: Bool = false) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.flat = flat
        let side = min(size.width, size.height)
        self.deck = deck ?? CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    var h: CGFloat { deck.height }
    private var dx: CGFloat { deck.minX }
    private var dy: CGFloat { deck.minY }
    /// Fast luft fra dækkets kant til alle detaljer (armbase, knapper, LED).
    var margin: CGFloat { h * 0.075 }

    // Tallerken og plade (lodret centreret)
    var center: CGPoint { CGPoint(x: dx + h * 0.42, y: dy + h * 0.5) }
    var platterRadius: CGFloat { h * 0.372 }
    var recordRadius: CGFloat { flat ? h * 0.372 : h * 0.357 }
    var grooveOuterRadius: CGFloat { flat ? h * 0.358 : h * 0.343 }
    var grooveInnerRadius: CGFloat { flat ? h * 0.196 : h * 0.172 }
    /// Flad: etiketten er ca. 47 % af pladens diameter (som på referencen).
    var labelRadius: CGFloat { flat ? recordRadius * 0.47 : h * 0.140 }
    var spindleRadius: CGFloat { h * 0.0105 }
    var holeRadius: CGFloat { h * 0.017 }

    /// Lodret kolonne langs dækkets højre side: armbase og LED står over hinanden her.
    var rightColumnX: CGFloat { deck.maxX - margin - basePlateRadius }

    // Pickuparm (lokale koordinater: omdrejningspunkt i (0,0), armen langs +x, +y = mod pladen i hvile)
    /// Flad: omdrejningspunktet højt og langt ude, så armen står næsten lodret ved pladens yderkant (som på referencen).
    /// Bundpladen og modvægten holdes altid inde på kroppen med samme luft (`flatEdgeGap`), også når dækket er større end kroppen.
    var pivot: CGPoint {
        guard flat else { return CGPoint(x: rightColumnX, y: dy + h * 0.235) }
        let gap = flatEdgeGap
        let x = min(deck.maxX - h * 0.105, size.width - gap - basePlateRadius)
        let y = max(dy + h * 0.18, gap + basePlateRadius, gap + abs(counterweightEnd) + counterweightRadius * 0.3)
        return CGPoint(x: x, y: y)
    }
    var flatEdgeGap: CGFloat { max(8, h * 0.03) }
    var tubeLength: CGFloat { flat ? h * 0.52 : h * 0.47 }
    /// Realistisk: aldrig tyndere end 3 pt, så røret kan ses som et rør i de små størrelser.
    var tubeWidth: CGFloat { flat ? max(1.6, h * 0.017) : max(3, h * 0.021) }
    var headshellLength: CGFloat { flat ? h * 0.10 : h * 0.088 }
    var headshellWidth: CGFloat { flat ? h * 0.052 : h * 0.044 }
    var headshellAngle: CGFloat { 24 * .pi / 180 }
    /// Modvægten bag lejet: rund cylinder fra start til slut langs armen (negativ x), halv bredde = radius.
    var counterweightStart: CGFloat { flat ? -h * 0.065 : -h * 0.062 }
    var counterweightEnd: CGFloat { -h * 0.125 }
    var counterweightRadius: CGFloat { flat ? h * 0.034 : h * 0.031 }
    /// Det runde kardanleje (sort hus med hætte).
    var bearingRadius: CGFloat { flat ? h * 0.040 : h * 0.036 }
    /// Rund bundplade under lejet (fast på kroppen).
    var basePlateRadius: CGFloat { flat ? h * 0.072 : h * 0.068 }
    /// Nålens plads på pickuphovedet (andel af længden), lige bag pickuppens front.
    var stylusAt: CGFloat { 0.92 }

    /// Pickupnålens position i armens lokale koordinater.
    var stylusLocal: CGPoint {
        CGPoint(x: tubeLength + headshellLength * stylusAt * cos(headshellAngle),
                y: headshellLength * stylusAt * sin(headshellAngle))
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

    // Små detaljer på dækket: på gitteret, nederst til højre, med `margin` til kanterne
    var detailRowY: CGFloat { deck.maxY - margin - speedButtonRadius }
    var ledCenter: CGPoint { CGPoint(x: rightColumnX, y: detailRowY) }
    var ledRadius: CGFloat { max(1.6, h * 0.0115) }
    var speedButtons: [CGPoint] {
        [CGPoint(x: rightColumnX - h * 0.19, y: detailRowY), CGPoint(x: rightColumnX - h * 0.095, y: detailRowY)]
    }
    var speedButtonRadius: CGFloat { h * 0.03 }
}
