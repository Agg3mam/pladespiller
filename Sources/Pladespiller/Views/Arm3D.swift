import AppKit
import SceneKit

/// Den realistiske pickuparm som en lille 3D-model (SceneKit), belyst med et studiemiljø og tegnet lige ovenfra
/// (ortografisk) én gang pr. størrelse. Billedet bruges præcis som det tegnede arm-billede: det drejer om lejet i
/// Core Animation, så CPU-forbruget er det samme. Bruges i Træ, Aluminium, Sort og Auto; Flad tegnes fladt (ArmRenderer).
///
/// Formen er som en DJ-pladespiller: riflet modvægt med sort nåletryksskive, kardanleje med åg, S-formet rør,
/// sølv låsering, sort pickuphoved med fingerløft, pickup med rød front og nålebøjle. Bundpladen med
/// antiskating-knappen tegnes som et separat billede (fast på kroppen).
///
/// Koordinater: armens lokale x → SceneKit x, lokale y (mod pladen) → SceneKit z, højde over kroppen → SceneKit y.
/// Kameraet ser ned ad −y med +z nedad i billedet, så billedet flugter med `ArmRenderer.bounds`.
enum Arm3D {
    /// Armen: samme udsnit som `ArmRenderer.bounds(g)`, i `scale` pixels pr. punkt. Nil hvis Metal mangler.
    static func image(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let scene = makeScene()
        scene.rootNode.addChildNode(armNode(g))
        return render(scene, rect: ArmRenderer.bounds(g), scale: scale)
    }

    /// Bundpladen (sort fod, drejet sølvring, antiskating-knap) centreret om lejet; udsnit `baseRect(g)` om (0,0).
    static func base(_ g: TurntableGeometry, scale: CGFloat) -> CGImage? {
        let scene = makeScene()
        scene.rootNode.addChildNode(baseNode(g))
        return render(scene, rect: baseRect(g), scale: scale)
    }

    static func baseRect(_ g: TurntableGeometry) -> CGRect {
        let r = g.basePlateRadius * 1.08
        return CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
    }

    // MARK: Scene, lys og materialer

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.5
        // Hovedlys fra øverst til venstre (samme retning som refleksen på pladen)
        let key = SCNLight()
        key.type = .directional
        key.intensity = 650
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.0, -0.65, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 80
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
        return scene
    }

    /// Studiemiljø (equirektangulært): mørkt rum med to store softboxe øverst til venstre og en smal lysstribe til
    /// højre, så metallet får tydelige lyse og mørke refleksioner i stedet for en jævn grå.
    private static var studioCache: CGImage?
    private static var studio: CGImage? {
        if let studioCache { return studioCache }
        studioCache = makeStudio()
        return studioCache
    }
    private static func makeStudio() -> CGImage? {
        let w = 1024, h = 512
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Drawing.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // himmel → gulv (CG: y opad, så toppen af billedet er "op")
        let sky = Drawing.gradient([(0, Drawing.gray(0.04)), (0.45, Drawing.gray(0.16)), (0.62, Drawing.gray(0.42)), (1, Drawing.gray(0.62))])
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
        func softbox(_ r: CGRect, _ v: CGFloat) {
            ctx.setFillColor(Drawing.gray(v))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.height * 0.3, cornerHeight: r.height * 0.3, transform: nil))
            ctx.fillPath()
        }
        softbox(CGRect(x: 90, y: 360, width: 260, height: 110), 1.0)
        softbox(CGRect(x: 380, y: 400, width: 150, height: 70), 0.85)
        softbox(CGRect(x: 690, y: 300, width: 40, height: 170), 0.95)
        softbox(CGRect(x: 880, y: 330, width: 90, height: 60), 0.55)
        return ctx.makeImage()
    }

    private static func material(_ color: NSColor, rough: CGFloat, metal: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        m.isDoubleSided = true
        return m
    }
    private static var aluminium: SCNMaterial { material(NSColor(white: 0.88, alpha: 1), rough: 0.24, metal: 1) }
    private static var brushed: SCNMaterial { material(NSColor(white: 0.84, alpha: 1), rough: 0.34, metal: 1) }
    private static var chrome: SCNMaterial { material(NSColor(white: 0.96, alpha: 1), rough: 0.07, metal: 1) }
    private static var anodizedBlack: SCNMaterial { material(NSColor(white: 0.03, alpha: 1), rough: 0.5, metal: 0.18) }
    private static var plasticBlack: SCNMaterial { material(NSColor(white: 0.05, alpha: 1), rough: 0.5, metal: 0) }
    private static var cartridgeRed: SCNMaterial {
        material(NSColor(srgbRed: 0.78, green: 0.19, blue: 0.14, alpha: 1), rough: 0.38, metal: 0)
    }
    private static var gold: SCNMaterial { material(NSColor(srgbRed: 0.85, green: 0.68, blue: 0.36, alpha: 1), rough: 0.25, metal: 1) }
    private static var white: SCNMaterial { material(NSColor(white: 0.92, alpha: 1), rough: 0.5, metal: 0) }

    // MARK: Geometri

    /// Drejet emne: profilen (radius, højde) drejes om y-aksen. Glatte normaler langs profilen.
    /// Profilen skal gå nedefra og op (bund → side → låg), så normalerne vender udad.
    private static func lathe(_ profile: [(r: CGFloat, y: CGFloat)], segments: Int = 72, _ m: SCNMaterial) -> SCNNode {
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
        let n = profile.count
        for (i, p) in profile.enumerated() {
            // normal i profilplanet: vinkelret på tangenten (gennemsnit af naboerne)
            let a = profile[max(0, i - 1)], b = profile[min(n - 1, i + 1)]
            var tr = b.r - a.r, ty = b.y - a.y
            let tl = max(1e-6, hypot(tr, ty)); tr /= tl; ty /= tl
            let nr = ty, ny = -tr
            for s in 0...segments {
                let phi = CGFloat(s) / CGFloat(segments) * 2 * .pi
                verts.append(SCNVector3(p.r * cos(phi), p.y, p.r * sin(phi)))
                normals.append(SCNVector3(nr * cos(phi), ny, nr * sin(phi)))
            }
        }
        let ring = segments + 1
        for i in 0..<(n - 1) {
            for s in 0..<segments {
                let a = Int32(i * ring + s), b = a + 1, c = Int32((i + 1) * ring + s), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geo.materials = [m]
        let node = SCNNode(geometry: geo)
        return node
    }

    /// Profil med fladt låg og afrundet kant (radius `bevel`) – sådan fanger kanten lyset ovenfra.
    private static func disc(r: CGFloat, height: CGFloat, bevel: CGFloat) -> [(r: CGFloat, y: CGFloat)] {
        var p: [(r: CGFloat, y: CGFloat)] = [(0, height)]
        p.append((r - bevel, height))
        for k in 1...8 {
            let a = CGFloat(k) / 8 * .pi / 2
            p.append((r - bevel + bevel * sin(a), height - bevel + bevel * cos(a)))
        }
        p.append((r, 0))
        return p.reversed()      // nedefra og op
    }

    /// Rør langs en kurve i xz-planet (glat, 24 sider), i højden `y`.
    private static func sweep(_ pts: [CGPoint], radius: CGFloat, y: CGFloat, _ m: SCNMaterial) -> SCNNode {
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
        let sides = 24
        for (i, p) in pts.enumerated() {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            var tx = b.x - a.x, tz = b.y - a.y
            let tl = max(1e-6, hypot(tx, tz)); tx /= tl; tz /= tl
            let sx = -tz, sz = tx                     // sidevektor i planet; "op" er +y
            for s in 0...sides {
                let phi = CGFloat(s) / CGFloat(sides) * 2 * .pi
                let ny = cos(phi), ns = sin(phi)
                normals.append(SCNVector3(sx * ns, ny, sz * ns))
                verts.append(SCNVector3(p.x + sx * ns * radius, y + ny * radius, p.y + sz * ns * radius))
            }
        }
        let ring = sides + 1
        for i in 0..<(pts.count - 1) {
            for s in 0..<sides {
                let a = Int32(i * ring + s), b = a + 1, c = Int32((i + 1) * ring + s), d = c + 1
                idx += [a, b, c, b, d, c]
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geo.materials = [m]
        let node = SCNNode(geometry: geo)
        // runde ender
        for p in [pts.first!, pts.last!] {
            let cap = SCNSphere(radius: radius); cap.segmentCount = 24; cap.materials = [m]
            let c = SCNNode(geometry: cap); c.position = SCNVector3(p.x, y, p.y)
            node.addChildNode(c)
        }
        return node
    }

    /// Lægger et drejet emne ned langs x-aksen (fra lodret y) og flytter det til `x`.
    private static func alongX(_ node: SCNNode, x: CGFloat, y: CGFloat) -> SCNNode {
        let holder = SCNNode()
        node.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)   // +y → +x
        holder.addChildNode(node)
        holder.position = SCNVector3(x, y, 0)
        return holder
    }

    private static func armNode(_ g: TurntableGeometry) -> SCNNode {
        let h = g.h, arm = SCNNode()
        let tubeR = g.tubeWidth * 0.5, y0 = h * 0.045          // rørets midte over kroppen
        let L = g.tubeLength, ang = g.headshellAngle

        // S-formet rør (samme kurve som den flade arm)
        let p0 = CGPoint(x: -h * 0.004, y: 0), p1 = CGPoint(x: L * 0.35, y: L * 0.13)
        let p2 = CGPoint(x: L - L * 0.30 * cos(ang), y: -L * 0.30 * sin(ang))
        let p3 = CGPoint(x: L - h * 0.012 * cos(ang), y: -h * 0.012 * sin(ang))
        let curve: [CGPoint] = (0...80).map { i in
            let t = CGFloat(i) / 80, u = 1 - t
            return CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                           y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
        }
        arm.addChildNode(sweep(curve, radius: tubeR, y: y0, aluminium))
        // bagerste stump
        arm.addChildNode(sweep([CGPoint(x: g.counterweightEnd + h * 0.006, y: 0), CGPoint(x: 0, y: 0)], radius: tubeR * 0.85, y: y0, chrome))

        // Modvægt: riflet bagtil (tætte riller fanger lyset), glat fortil, afrundede kanter
        let cwL = g.counterweightStart - g.counterweightEnd, cwR = g.counterweightRadius
        var cw: [(r: CGFloat, y: CGFloat)] = [(0, 0), (cwR * 0.9, 0), (cwR, cwR * 0.1)]
        var y = cwR * 0.1
        let knurlEnd = cwL * 0.45, pitch = h * 0.0042
        while y < knurlEnd {
            cw.append((cwR, y)); cw.append((cwR * 0.955, y + pitch * 0.5)); y += pitch
        }
        cw += [(cwR, knurlEnd + pitch * 0.5), (cwR, cwL - cwR * 0.1), (cwR * 0.9, cwL), (0, cwL)]
        arm.addChildNode(alongX(lathe(cw, brushed), x: g.counterweightEnd, y: y0))
        // nåletryksskive (sort) med hvide streger og rødt nulpunkt
        let dw = h * 0.016
        arm.addChildNode(alongX(lathe(disc(r: cwR * 1.04, height: dw, bevel: dw * 0.3), anodizedBlack),
                                x: g.counterweightStart - dw, y: y0))
        for i in -4...4 {
            let tick = SCNBox(width: dw * (i == 0 ? 0.7 : 0.4), height: h * 0.0012, length: h * 0.0011, chamferRadius: 0)
            tick.materials = [i == 0 ? cartridgeRed : white]
            let a = CGFloat(i) * 0.16
            let t = SCNNode(geometry: tick)
            t.position = SCNVector3(g.counterweightStart - dw * 0.5, y0 + cwR * 1.04 * cos(a), cwR * 1.04 * sin(a))
            arm.addChildNode(t)
        }

        // Kardanleje: sølvhus med afrundet kant, krom hætte med en lille kuppel, åg med to tapper på tværs
        let b = g.bearingRadius
        let housing = lathe(disc(r: b, height: y0 + b * 0.35, bevel: b * 0.25), aluminium)
        arm.addChildNode(housing)
        var cap = disc(r: b * 0.55, height: y0 + b * 0.55, bevel: b * 0.2)
        cap.append((0, y0 + b * 0.62))     // lille kuppel
        arm.addChildNode(lathe(cap, chrome))
        // åg: en rund tværstang over huset, båret af to små stolper ude ved kanten
        arm.addChildNode(sweep([CGPoint(x: 0, y: -(b + h * 0.008)), CGPoint(x: 0, y: b + h * 0.008)], radius: h * 0.0065,
                               y: y0 + b * 0.25, brushed))
        for side in [-1.0, 1.0] as [CGFloat] {
            let post = lathe(disc(r: h * 0.009, height: y0 + b * 0.3, bevel: h * 0.003), aluminium)
            post.position = SCNVector3(0, 0, side * (b + h * 0.004))
            arm.addChildNode(post)
        }
        for side in [-1.0, 1.0] as [CGFloat] {
            let pin = lathe(disc(r: h * 0.006, height: h * 0.008, bevel: h * 0.002), chrome)
            pin.eulerAngles = SCNVector3(side * CGFloat.pi / 2, 0, 0)
            pin.position = SCNVector3(0, y0, side * (b + h * 0.012))
            arm.addChildNode(pin)
        }

        // Pickuphoved i sin vinkel: låsering, sort plade med fasede kanter, pickup, skruer, nålebøjle, fingerløft
        let hs = SCNNode()
        hs.position = SCNVector3(L, y0, 0)
        hs.eulerAngles = SCNVector3(0, -ang, 0)
        arm.addChildNode(hs)
        let ringL = h * 0.024
        var ring: [(r: CGFloat, y: CGFloat)] = [(0, 0), (tubeR * 1.6, 0)]
        for k in 0..<5 { let yy = ringL * CGFloat(k) / 5; ring += [(tubeR * 2.05, yy + ringL * 0.04), (tubeR * 1.9, yy + ringL * 0.12)] }
        ring += [(tubeR * 2.05, ringL * 0.96), (tubeR * 1.6, ringL), (0, ringL)]
        hs.addChildNode(alongX(lathe(ring, chrome), x: -h * 0.03, y: 0))

        let hl = g.headshellLength, hw = g.headshellWidth
        let plate = NSBezierPath()
        plate.move(to: NSPoint(x: -h * 0.006, y: -tubeR * 1.7))
        plate.line(to: NSPoint(x: hl * 0.28, y: -hw / 2))
        plate.line(to: NSPoint(x: hl * 0.97, y: -hw / 2))
        plate.curve(to: NSPoint(x: hl * 0.97, y: hw / 2), controlPoint1: NSPoint(x: hl * 1.03, y: -hw / 4), controlPoint2: NSPoint(x: hl * 1.03, y: hw / 4))
        plate.line(to: NSPoint(x: hl * 0.28, y: hw / 2))
        plate.line(to: NSPoint(x: -h * 0.006, y: tubeR * 1.7))
        plate.close()
        plate.flatness = 0.05
        let shell = SCNShape(path: plate, extrusionDepth: h * 0.007)
        shell.chamferRadius = h * 0.0022
        shell.materials = [anodizedBlack]
        let shellNode = SCNNode(geometry: shell)
        shellNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)        // xy-profilen ned i xz-planet (y → z)
        shellNode.position = SCNVector3(0, h * 0.002, 0)
        hs.addChildNode(shellNode)

        // pickuppen er lidt bredere end hovedet og stikker frem foran det (som på billedet), så den kan ses ovenfra
        let cartW = hl * 0.62, cartD = hw * 0.84, cartH = h * 0.018
        let cart = SCNBox(width: cartW, height: cartH, length: cartD, chamferRadius: h * 0.003)
        cart.materials = [plasticBlack]
        let cartNode = SCNNode(geometry: cart); cartNode.position = SCNVector3(hl * 0.74, -cartH * 0.45, 0)
        hs.addChildNode(cartNode)
        let front = SCNBox(width: hl * 0.14, height: cartH * 0.9, length: cartD * 0.92, chamferRadius: h * 0.003)
        front.materials = [cartridgeRed]
        let frontNode = SCNNode(geometry: front); frontNode.position = SCNVector3(hl * 1.0, -cartH * 0.45, 0)
        hs.addChildNode(frontNode)
        for zz in [-hw * 0.17, hw * 0.17] {
            let screw = SCNSphere(radius: h * 0.0042); screw.materials = [chrome]
            let s = SCNNode(geometry: screw); s.position = SCNVector3(hl * 0.55, h * 0.0055, zz); s.scale = SCNVector3(1, 0.45, 1)
            hs.addChildNode(s)
        }
        hs.addChildNode(sweep([CGPoint(x: hl * 1.05, y: 0), CGPoint(x: hl * 1.10, y: 0)], radius: h * 0.0016, y: -cartH * 0.5, gold))
        let lift: [CGPoint] = (0...20).map { i in
            let t = CGFloat(i) / 20
            return CGPoint(x: hl * (0.50 + 0.30 * t), y: -hw * (0.46 + 0.86 * t * (2 - t)))
        }
        hs.addChildNode(sweep(lift, radius: h * 0.0038, y: h * 0.004, chrome))
        return arm
    }

    private static func baseNode(_ g: TurntableGeometry) -> SCNNode {
        let h = g.h, br = g.basePlateRadius, node = SCNNode()
        // sort fod med afrundet kant og et lille trin
        node.addChildNode(lathe(disc(r: br, height: h * 0.012, bevel: h * 0.005), anodizedBlack))
        node.addChildNode(lathe(disc(r: br * 0.86, height: h * 0.016, bevel: h * 0.002), anodizedBlack))
        // drejet sølvring med tætte riller (lyset tegner ringe)
        var ring: [(r: CGFloat, y: CGFloat)] = [(0, h * 0.024)]
        var r: CGFloat = br * 0.1
        while r < br * 0.6 { ring += [(r, h * 0.024), (r + h * 0.0012, h * 0.0236)]; r += h * 0.0024 }
        ring += [(br * 0.62, h * 0.022), (br * 0.62, h * 0.016)]
        node.addChildNode(lathe(ring.reversed(), segments: 96, aluminium))
        // antiskating-knap: sort, riflet kant, hvid streg
        let kr = br * 0.24, ka: CGFloat = -0.35
        let knob: [(r: CGFloat, y: CGFloat)] = [(kr, h * 0.016), (kr, h * 0.024), (kr * 0.95, h * 0.028), (kr * 0.8, h * 0.03), (0, h * 0.03)]
        let knobNode = lathe(knob, plasticBlack)
        knobNode.position = SCNVector3(br * 0.78 * cos(ka), 0, br * 0.78 * sin(ka))
        node.addChildNode(knobNode)
        for i in 0..<36 {
            let a = CGFloat(i) / 24 * 2 * .pi
            let rib = SCNBox(width: h * 0.0012, height: h * 0.012, length: h * 0.0012, chamferRadius: 0)
            rib.materials = [anodizedBlack]
            let rn = SCNNode(geometry: rib)
            rn.position = SCNVector3(knobNode.position.x + kr * cos(a), h * 0.022, knobNode.position.z + kr * sin(a))
            rn.eulerAngles = SCNVector3(0, -a, 0)
            node.addChildNode(rn)
        }
        let mark = SCNBox(width: kr * 0.7, height: h * 0.001, length: h * 0.0022, chamferRadius: 0)
        mark.materials = [white]
        let mn = SCNNode(geometry: mark)
        mn.position = SCNVector3(knobNode.position.x + kr * 0.35 * cos(-1.2), h * 0.0305, knobNode.position.z + kr * 0.35 * sin(-1.2))
        mn.eulerAngles = SCNVector3(0, 1.2, 0)
        node.addChildNode(mn)
        return node
    }

    // MARK: Tegning

    private static var rendererCache: SCNRenderer?
    private static var renderer: SCNRenderer? {
        if rendererCache == nil, let device = MTLCreateSystemDefaultDevice() { rendererCache = SCNRenderer(device: device, options: nil) }
        return rendererCache
    }

    /// Tegner scenen lige ovenfra, så `rect` (lokale punkter, y nedad) fylder billedet. 4x multisampling.
    private static func render(_ scene: SCNScene, rect: CGRect, scale: CGFloat) -> CGImage? {
        guard let renderer else { return nil }
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(rect.height / 2)
        cam.zNear = 1
        cam.zFar = Double(rect.width * 20 + 1000)
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(rect.midX, rect.width * 5 + 500, rect.midY)
        camNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        scene.rootNode.addChildNode(camNode)
        renderer.scene = scene
        renderer.pointOfView = camNode
        let size = CGSize(width: (rect.width * scale).rounded(.up), height: (rect.height * scale).rounded(.up))
        let img = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        var r = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }
}
