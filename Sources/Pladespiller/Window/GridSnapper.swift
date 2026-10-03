import CoreGraphics

/// Ren gitterlogik (ingen AppKit, intet vindue) – kan testes direkte.
///
/// Alle rammer er i AppKit-koordinater (origin nederst til venstre, y opad).
///
/// Sådan placerer Apple sine widgets (aflæst i `com.apple.notificationcenterui`
/// › `widgets` › `DesktopWidgetPlacementStorage`, 2026-10-03): widgets ligger i *grupper*.
/// Hver gruppe har et frit `Origin` målt fra det synlige områdes øverste venstre hjørne
/// (hos brugeren `[313, 0]`), og widgets i gruppen ligger på `Column`/`Row` i et 180 pt-gitter
/// fra dét origin. Gitteret er altså ikke fast på skærmen – det følger gruppen.
///
/// Derfor: findes der Apple-widgets på skærmen, flugter vi med den nærmeste af dem
/// (gitterlinjer = dens kanter + k·180). Ellers bruges et gitter fra det synlige områdes
/// øverste venstre hjørne. Vi lægger os aldrig oven på en Apple-widget og holder os
/// inden for det synlige område.
nonisolated enum GridSnapper {

    /// Et gitter: celler har venstre kant ≡ `left` og øverste kant ≡ `top` (mod `pitch`).
    struct Grid: Equatable {
        var left: CGFloat
        var top: CGFloat
        var pitch: CGFloat
    }

    /// Vælger gitteret: den Apple-widget der ligger nærmest `frame`'s midtpunkt
    /// (kun widgets der rører `visibleFrame`), ellers det synlige områdes øverste venstre hjørne.
    static func grid(for frame: CGRect, visibleFrame: CGRect, anchors: [CGRect], pitch: CGFloat) -> Grid {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let onScreen = anchors.filter { $0.intersects(visibleFrame) }
        if let nearest = onScreen.min(by: { distance(center, $0) < distance(center, $1) }) {
            return Grid(left: nearest.minX, top: nearest.maxY, pitch: pitch)
        }
        return Grid(left: visibleFrame.minX, top: visibleFrame.maxY, pitch: pitch)
    }

    /// Den celle i gitteret der ligger nærmest `frame`, som er helt inden for `visibleFrame`
    /// og ikke overlapper nogen af `anchors`. Findes ingen, klemmes `frame` blot ind i `visibleFrame`.
    static func snap(_ frame: CGRect, visibleFrame: CGRect, anchors: [CGRect],
                     pitch: CGFloat = 180) -> CGRect {
        let grid = grid(for: frame, visibleFrame: visibleFrame, anchors: anchors, pitch: pitch)
        return snap(frame, to: grid, visibleFrame: visibleFrame, anchors: anchors)
    }

    static func snap(_ frame: CGRect, to grid: Grid, visibleFrame: CGRect, anchors: [CGRect]) -> CGRect {
        let p = grid.pitch
        let w = frame.width, h = frame.height
        let i0 = Int(((frame.minX - grid.left) / p).rounded())
        let j0 = Int(((grid.top - frame.maxY) / p).rounded())

        func cell(_ i: Int, _ j: Int) -> CGRect {
            CGRect(x: grid.left + CGFloat(i) * p, y: grid.top - CGFloat(j) * p - h, width: w, height: h)
        }
        func isFree(_ r: CGRect) -> Bool {
            guard visibleFrame.insetBy(dx: -0.5, dy: -0.5).contains(r) else { return false }
            return !anchors.contains { a in
                let x = a.intersection(r)
                return !x.isNull && x.width > 1 && x.height > 1
            }
        }

        // Søg i ringe udad, til der er dækket hele det synlige område.
        let maxRadius = Int((max(visibleFrame.width, visibleFrame.height) / p).rounded(.up)) + 2
        var best: CGRect?
        var bestDistance = CGFloat.infinity
        for radius in 0...maxRadius {
            for i in (i0 - radius)...(i0 + radius) {
                for j in (j0 - radius)...(j0 + radius)
                where max(abs(i - i0), abs(j - j0)) == radius {
                    let r = cell(i, j)
                    guard isFree(r) else { continue }
                    let d = hypot(r.minX - frame.minX, r.minY - frame.minY)
                    if d < bestDistance { bestDistance = d; best = r }
                }
            }
            // En celle i ring k er mindst (k-1)·p væk; stop når ingen længere ring kan slå den.
            if best != nil, CGFloat(radius) * p > bestDistance + p { break }
        }
        return best ?? clamp(frame, into: visibleFrame)
    }

    /// Flytter `frame` (uden at ændre størrelse) så den ligger inden for `bounds`.
    static func clamp(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        var r = frame
        r.origin.x = min(max(r.minX, bounds.minX), max(bounds.minX, bounds.maxX - r.width))
        r.origin.y = min(max(r.minY, bounds.minY), max(bounds.minY, bounds.maxY - r.height))
        return r
    }

    /// Den skærm (visibleFrame) som en ramme hører til: størst overlap, ellers nærmest.
    static func bestScreenIndex(for frame: CGRect, visibleFrames: [CGRect]) -> Int? {
        guard !visibleFrames.isEmpty else { return nil }
        let areas = visibleFrames.map { v -> CGFloat in
            let x = v.intersection(frame)
            return x.isNull ? 0 : x.width * x.height
        }
        if let m = areas.max(), m > 0 { return areas.firstIndex(of: m) }
        let c = CGPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.indices.min { distance(c, visibleFrames[$0]) < distance(c, visibleFrames[$1]) }
    }

    /// Afstand fra et punkt til et rektangel (0 hvis indeni).
    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    /// CGWindowList-rammer (origin øverst til venstre på hovedskærmen) → AppKit-rammer.
    static func appKitRect(fromCG r: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
    }
}
