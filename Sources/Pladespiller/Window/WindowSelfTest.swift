import AppKit
import SwiftUI

/// `--window-selftest [mappe]`: tester gitterlogik og stil-aflæsning uden vindue og tegner
/// skallen (lys/mørk, alle størrelser) til PNG i `mappe`, så den kan sammenlignes med Apples
/// widget-billeder. Returnerer antal fejl.
enum WindowSelfTest {
    private final class Tally { var failures = 0 }

    @discardableResult
    static func run(outputDirectory: URL? = nil) -> Int {
        let tally = Tally()
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print(ok ? "OK   " : "FEJL ", name, ok ? "" : detail())
            if !ok { tally.failures += 1 }
        }

        // Brugerens hovedskærm: 1710×1112, menulinje 38 → visibleFrame (0,0,1710,1074) i AppKit.
        let screenH: CGFloat = 1112
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1074)
        let p: CGFloat = 180
        func cg(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            GridSnapper.appKitRect(fromCG: CGRect(x: x, y: y, width: w, height: h), primaryScreenHeight: screenH)
        }
        // Apples widgets som målt (CG-koordinater).
        let apple = [cg(313, 38, 360, 180), cg(313, 218, 360, 180), cg(673, 38, 360, 360), cg(1033, 38, 180, 180)]
        let medium = CGSize(width: 360, height: 180)

        check("CG→AppKit", apple[0] == CGRect(x: 313, y: 894, width: 360, height: 180), "\(apple[0])")

        // 1. Sluppet lidt skævt til højre for Ur-widgetten → flugter i kolonnen x=1213, y=38 (CG).
        do {
            let dropped = cg(1225, 47, 360, 180)
            let r = GridSnapper.snap(dropped, visibleFrame: visible, anchors: apple, pitch: p)
            check("snap ved siden af Ur", r == cg(1213, 38, 360, 180), "\(r)")
        }
        // 2. Sluppet oven på Status-widgetten → nærmeste ledige celle, ikke overlap.
        do {
            let dropped = cg(700, 60, 360, 180)
            let r = GridSnapper.snap(dropped, visibleFrame: visible, anchors: apple, pitch: p)
            let overlaps = apple.contains { $0.intersection(r).width > 1 && $0.intersection(r).height > 1 }
            check("ingen overlap med Apple", !overlaps && visible.contains(r), "\(r)")
            check("på Apples gitter", (r.minX - 313).truncatingRemainder(dividingBy: p) == 0
                  && (apple[0].maxY - r.maxY).truncatingRemainder(dividingBy: p) == 0, "\(r)")
        }
        // 3. Under Kalender (række 2) → x=313, y=398 (CG).
        do {
            let dropped = cg(330, 380, 360, 180)
            let r = GridSnapper.snap(dropped, visibleFrame: visible, anchors: apple, pitch: p)
            check("under Kalender", r == cg(313, 398, 360, 180), "\(r)")
        }
        // 4. Ingen Apple-widgets → gitter fra synligt områdes øverste venstre hjørne.
        do {
            let dropped = cg(200, 130, 360, 180)
            let r = GridSnapper.snap(dropped, visibleFrame: visible, anchors: [], pitch: p)
            check("fast gitter uden Apple", r == cg(180, 218, 360, 180), "\(r)")
        }
        // 5. Uden for skærmen til højre/nederst → klemmes ind og snappes.
        do {
            let dropped = cg(1650, 1050, 360, 180)
            let r = GridSnapper.snap(GridSnapper.clamp(dropped, into: visible),
                                     visibleFrame: visible, anchors: apple, pitch: p)
            check("klemt ind fra kanten", visible.contains(r), "\(r)")
        }
        // 6. Idempotent.
        do {
            let r1 = GridSnapper.snap(cg(900, 700, 360, 360), visibleFrame: visible, anchors: apple, pitch: p)
            let r2 = GridSnapper.snap(r1, visibleFrame: visible, anchors: apple, pitch: p)
            check("snap er idempotent", r1 == r2, "\(r1) \(r2)")
        }
        // 7. Skærm-valg: ramme på ingen skærm → nærmeste.
        do {
            let screens = [visible, CGRect(x: 1710, y: 0, width: 1920, height: 1050)]
            check("skærm med størst overlap",
                  GridSnapper.bestScreenIndex(for: CGRect(x: 1650, y: 10, width: 360, height: 180), visibleFrames: screens) == 1)
            check("nærmeste skærm",
                  GridSnapper.bestScreenIndex(for: CGRect(x: -900, y: 10, width: 360, height: 180), visibleFrames: screens) == 0)
        }
        _ = medium
        // 8. Stil-aflæsning.
        check("RegularDark", WidgetStyle.parse(iconTheme: "RegularDark") == (.opaque, .dark))
        check("ClearLight", WidgetStyle.parse(iconTheme: "ClearLight") == (.glass, .light))
        check("TintedAutomatic", WidgetStyle.parse(iconTheme: "TintedAutomatic") == (.glass, nil))
        check("ingen nøgle", WidgetStyle.parse(iconTheme: nil) == (.opaque, nil))

        // 8b. Størrelsesskift fra samme øverste venstre hjørne (QA N15): ingen "drift".
        do {
            let topLeft = CGPoint(x: 133, y: visible.maxY)   // CG (133, 38)
            func place(_ s: WidgetSize) -> CGRect {
                let size = WidgetMetrics.windowSize(for: s)
                let r = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
                return GridSnapper.snap(GridSnapper.clamp(r, into: visible), visibleFrame: visible, anchors: apple, pitch: p)
            }
            let small1 = place(.small), medium = place(.medium), small2 = place(.small)
            check("Lille på ønsket plads", small1 == cg(133, 38, 180, 180), "\(small1)")
            check("Mellem viger for Apple (overlap ved x=313)", !apple.contains { $0.intersects(medium.insetBy(dx: 1, dy: 1)) }, "\(medium)")
            check("Lille tilbage på samme plads", small2 == small1, "\(small2)")
        }

        // 9. Falmet look.
        typealias D = WidgetDimming
        check("Fuld farve-stil → aldrig dæmpet", D.target(mode: .automatic, policy: .fullColor, desktopFocused: false) == 0)
        check("Automatisk, andet program aktivt → dæmpet", D.target(mode: .automatic, policy: .automatic, desktopFocused: false) == 1)
        check("Automatisk, skrivebord i fokus → fuld farve", D.target(mode: .automatic, policy: .automatic, desktopFocused: true) == 0)
        check("Altid dæmpet", D.target(mode: .alwaysDimmed, policy: .fullColor, desktopFocused: true) == 1)
        check("Altid fuld farve", D.target(mode: .alwaysFull, policy: .automatic, desktopFocused: false) == 0)
        check("widgetAppearance 1 = Fuld farve", D.systemPolicy(widgetAppearance: 1) == .fullColor)
        check("Cmd+Tab til Finder med vinduer → dæmpet", D.desktopFocusOnFinderActivation(clickedDesktop: nil, finderHasWindows: true) == false)
        check("Klik på skrivebordet → fuld farve", D.desktopFocusOnFinderActivation(clickedDesktop: true, finderHasWindows: true))
        check("Klik i Finder-vindue → dæmpet", D.desktopFocusOnFinderActivation(clickedDesktop: false, finderHasWindows: true) == false)
        check("Finder uden vinduer → fuld farve", D.desktopFocusOnFinderActivation(clickedDesktop: nil, finderHasWindows: false))
        check("widgetAppearance ukendt = Automatisk", D.systemPolicy(widgetAppearance: nil) == .automatic)

        // 10. Menu.
        do {
            let defaults = UserDefaults(suiteName: "pladespiller.selftest.menu") ?? .standard
            let settings = Settings(defaults: defaults)
            settings.size = .large
            settings.theme = .black
            let builder = WidgetMenu(settings: settings)   // holder handlingerne (target er svag)
            let menu = builder.build()
            let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            print("     menu:", titles.joined(separator: " | "))
            check("menupunkter", titles == ["Lille", "Mellem", "Stor", "—", "Tema", "Farve", "Hastighed", "Dæmpning", "—",
                                            "Vis knapper og tekst", "Vis sangtekst", "Henter fra LRCLIB på nettet", "—",
                                            "Lås placering", "Åbn ved login", "—", "Fjern widget"], "\(titles)")
            check("flueben ved Stor", menu.item(withTitle: "Stor")?.state == .on && menu.item(withTitle: "Lille")?.state == .off)
            let tema = menu.item(withTitle: "Tema")?.submenu
            check("Tema-undermenu", tema?.items.map(\.title) == ["Flad", "Træ", "Aluminium", "Sort", "Auto"]
                  && tema?.item(withTitle: "Sort")?.state == .on)
            check("Dæmpning-undermenu", menu.item(withTitle: "Dæmpning")?.submenu?.items.map(\.title)
                  == ["Automatisk", "Altid fuld farve", "Altid dæmpet"])
            // Vælg "Lille" og "Aluminium" via menuens egne handlinger.
            if let i = menu.item(withTitle: "Lille") , let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) }
            if let i = tema?.item(withTitle: "Aluminium") , let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) }
            check("menuhandling sætter indstillinger", settings.size == .small && settings.theme == .aluminium)
            settings.spinSpeed = .calm
            let hastighed = menu.item(withTitle: "Hastighed")?.submenu
            check("Hastighed-undermenu", hastighed?.items.map(\.title) == SpinSpeed.allCases.map(\.title)
                  && hastighed?.items.filter { $0.state == .on }.count == 1)
            if let i = hastighed?.item(withTitle: SpinSpeed.rpm45.title), let a = i.action {
                _ = (i.target as? NSObject)?.perform(a, with: i)
            }
            check("menuhandling sætter spinSpeed", settings.spinSpeed == .rpm45, "\(settings.spinSpeed)")

            // Farve ▸ (temaet Flad).
            let farve = menu.item(withTitle: "Farve")?.submenu
            let farveTitles = farve?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
            let fixed = FlatColor.allCases.filter { $0 != .auto && $0 != .custom }
            check("Farve-undermenu", farveTitles == ["Auto (fra coveret)", "—"] + fixed.map(\.title) + ["—", "Vælg farve…"],
                  "\(farveTitles)")
            check("farveprikker på faste farver", fixed.allSatisfy { farve?.item(withTitle: $0.title)?.image?.size == NSSize(width: 12, height: 12) })
            check("ingen flueben i Farve når tema ≠ Flad", farve?.items.allSatisfy { $0.state == .off } == true)
            if let i = farve?.item(withTitle: FlatColor.teal.title), let a = i.action {
                _ = (i.target as? NSObject)?.perform(a, with: i)
            }
            check("farvevalg sætter flatColor og skifter til Flad", settings.flatColor == .teal && settings.theme == .flat)
            do {
                let again = builder.build().item(withTitle: "Farve")?.submenu
                check("flueben ved Turkis", again?.item(withTitle: FlatColor.teal.title)?.state == .on
                      && again?.items.filter { $0.state == .on }.count == 1)
            }
            check("hex ud og ind", NSColor(hex: "1F9E95")?.srgbHex == "1F9E95" && NSColor(hex: "#f2b705")?.srgbHex == "F2B705")
            settings.flatColor = .custom
            settings.flatCustomHex = "123456"
            check("prik i valgt farve ved Vælg farve…",
                  builder.build().item(withTitle: "Farve")?.submenu?.item(withTitle: FlatColor.custom.title)?.image != nil)

            // Afkrydsninger.
            settings.showControls = false
            settings.showLyrics = true
            let m2 = builder.build()
            check("flueben følger showControls/showLyrics",
                  m2.item(withTitle: "Vis knapper og tekst")?.state == .off && m2.item(withTitle: "Vis sangtekst")?.state == .on)
            check("LRCLIB-note er deaktiveret", m2.item(withTitle: "Henter fra LRCLIB på nettet")?.isEnabled == false)
            for title in ["Vis knapper og tekst", "Vis sangtekst"] {
                if let i = m2.item(withTitle: title), let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) }
            }
            check("afkrydsninger skifter showControls/showLyrics", settings.showControls && !settings.showLyrics)
            withExtendedLifetime(builder) {}
            UserDefaults.standard.removePersistentDomain(forName: "pladespiller.selftest.menu")
        }

        // 11. Fuld skærm.
        do {
            typealias F = FullscreenController
            check("skærm: valgt og tilsluttet", F.chooseScreen(screenIDs: ["A", "B", "C"], preferredID: "C", widgetScreenID: nil) == "C")
            check("skærm: valgt men væk → automatisk", F.chooseScreen(screenIDs: ["A", "B"], preferredID: "X", widgetScreenID: nil) == "B")
            check("skærm: ikke hovedskærmen", F.chooseScreen(screenIDs: ["A", "B"], preferredID: nil, widgetScreenID: "A") == "B")
            check("skærm: helst ikke widgettens", F.chooseScreen(screenIDs: ["A", "B", "C"], preferredID: nil, widgetScreenID: "B") == "C")
            check("skærm: kun ekstra med widget → den alligevel", F.chooseScreen(screenIDs: ["A", "B"], preferredID: nil, widgetScreenID: "B") == "B")
            check("skærm: kun én", F.chooseScreen(screenIDs: ["A"], preferredID: nil, widgetScreenID: "A") == "A")
            check("skærm: ingen", F.chooseScreen(screenIDs: [], preferredID: nil, widgetScreenID: nil) == nil)
            check("tændt: kun når vist + spiller + slået til",
                  F.shouldHoldDisplayAwake(keepAwake: true, showing: true, playing: true)
                  && !F.shouldHoldDisplayAwake(keepAwake: true, showing: true, playing: false)
                  && !F.shouldHoldDisplayAwake(keepAwake: false, showing: true, playing: true)
                  && !F.shouldHoldDisplayAwake(keepAwake: true, showing: false, playing: true))

            check("fuld skærm-niveau = desktopIconWindow + 1 (-2147483602), under widgets",
                  FullscreenWindow.windowLevel.rawValue == -2147483602
                  && FullscreenWindow.windowLevel.rawValue < WidgetMetrics.windowLevel.rawValue
                  && FullscreenWindow.windowLevel.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow))
                  && FullscreenWindow.windowLevel.rawValue < NSWindow.Level.normal.rawValue)
            check("fuld skærm-collectionBehavior", FullscreenWindow.behavior == [.canJoinAllSpaces, .stationary, .ignoresCycle])

            // Flyt nye vinduer (CG-koordinater). Hovedskærm 1710×1112 til venstre, fuld skærm 2560×1440 til højre.
            typealias M = NewWindowMover
            let main = CGRect(x: 0, y: 0, width: 1710, height: 1112), mainVis = CGRect(x: 0, y: 38, width: 1710, height: 1074)
            let fsScreen = CGRect(x: 1710, y: 0, width: 2560, height: 1440), fsVis = CGRect(x: 1710, y: 30, width: 2560, height: 1410)
            check("helt på skærmen = 1", M.fractionOnScreen(CGRect(x: 2000, y: 200, width: 800, height: 600), screen: fsScreen) == 1)
            check("ikke på skærmen = 0", M.fractionOnScreen(CGRect(x: 100, y: 200, width: 800, height: 600), screen: fsScreen) == 0)
            let straddle = CGRect(x: 1510, y: 200, width: 800, height: 600)   // 600 af 800 på fuld skærm
            check("75 % på fuld skærm", abs(M.fractionOnScreen(straddle, screen: fsScreen) - 0.75) < 0.0001)
            check("præcis halvdelen tæller ikke (> 50 %)", !(M.fractionOnScreen(CGRect(x: 1310, y: 0, width: 800, height: 600), screen: fsScreen) > 0.5))
            _ = main
            let centered = CGRect(x: 1710 + 1280 - 400, y: 30 + 705 - 300, width: 800, height: 600)
            let moved = M.destinationFrame(window: centered, from: fsVis, to: mainVis)
            check("relativ placering bevares (centreret → centreret)",
                  abs(moved.midX - mainVis.midX) < 0.5 && abs(moved.midY - mainVis.midY) < 0.5 && moved.size == centered.size, "\(moved)")
            let topLeft = CGRect(x: 1710 + 10, y: 30 + 10, width: 600, height: 400)
            let movedTL = M.destinationFrame(window: topLeft, from: fsVis, to: mainVis)
            check("øverst til venstre forbliver øverst til venstre og indenfor",
                  mainVis.contains(movedTL) && movedTL.minX < 200 && movedTL.minY < 260, "\(movedTL)")
            let huge = CGRect(x: 1710, y: 30, width: 2400, height: 1350)
            let shrunk = M.destinationFrame(window: huge, from: fsVis, to: mainVis)
            check("for stort vindue krympes til målets synlige område", shrunk == mainVis, "\(shrunk)")

            let a = DisplayAwakeAssertion()
            a.take()
            let held = a.isHeld
            a.take()   // idempotent
            a.release()
            check("IOPM-assertion tages og slippes", held && !a.isHeld)

            let defaults = UserDefaults(suiteName: "pladespiller.selftest.fs") ?? .standard
            let settings = Settings(defaults: defaults)
            settings.fullscreenScreenID = nil
            settings.fullscreenLayout = .lyrics
            settings.keepDisplayAwake = true
            let fs = FullscreenController(settings: settings) { Color.black }
            fs.isPlaying = true
            check("ingen assertion når fuld skærm ikke vises", !fs.holdsDisplayAwake)
            let builder = WidgetMenu(settings: settings)
            builder.fullscreen = fs
            builder.screens = { [("A", "Indbygget skærm"), ("B", "LG UltraFine")] }
            let menu = builder.build()
            let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            check("fuld skærm-gruppe efter Vis sangtekst",
                  Array(titles.drop { $0 != "Henter fra LRCLIB på nettet" }.prefix(8))
                  == ["Henter fra LRCLIB på nettet", "—", "Fuld skærm", "Fuld skærm-visning", "Fuld skærm-skærm",
                      "Hold skærmen tændt", "Flyt nye vinduer væk", "—"], "\(titles)")
            check("Flyt nye vinduer væk: flueben = indstilling",
                  menu.item(withTitle: "Flyt nye vinduer væk")?.state == (NewWindowMover.isEnabled ? .on : .off))
            check("Fuld skærm: tooltip + intet flueben", menu.item(withTitle: "Fuld skærm")?.toolTip == "Esc lukker"
                  && menu.item(withTitle: "Fuld skærm")?.state == .off)
            let vis = menu.item(withTitle: "Fuld skærm-visning")?.submenu
            check("Fuld skærm-visning", vis?.items.map(\.title) == ["Med sangtekst", "Kun pladespiller"]
                  && vis?.item(withTitle: "Med sangtekst")?.state == .on)
            let sk = menu.item(withTitle: "Fuld skærm-skærm")?.submenu
            check("Fuld skærm-skærm", sk?.items.map { $0.isSeparatorItem ? "—" : $0.title }
                  == ["Automatisk", "—", "Indbygget skærm", "LG UltraFine"] && sk?.item(withTitle: "Automatisk")?.state == .on)
            func fire(_ i: NSMenuItem?) { if let i, let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) } }
            fire(vis?.item(withTitle: "Kun pladespiller"))
            fire(sk?.item(withTitle: "LG UltraFine"))
            fire(menu.item(withTitle: "Hold skærmen tændt"))
            check("fuld skærm-handlinger sætter indstillinger",
                  settings.fullscreenLayout == .turntable && settings.fullscreenScreenID == "B" && !settings.keepDisplayAwake)
            builder.screens = { [("A", "Indbygget skærm")] }
            check("Fuld skærm-skærm skjult ved én skærm", builder.build().item(withTitle: "Fuld skærm-skærm") == nil)
            withExtendedLifetime(builder) {}
            withExtendedLifetime(fs) {}
            UserDefaults.standard.removePersistentDomain(forName: "pladespiller.selftest.fs")
        }

        let live = WidgetStyle()
        print("     system: AppleIconAppearanceTheme=\(live.iconTheme ?? "–") widgetAppearance=\(live.widgetAppearance.map(String.init) ?? "–") → \(live.material), \(String(describing: live.forcedScheme))")
        print("     Apple-widgets nu:", AppleWidgetWindows.frames())

        if let dir = outputDirectory { renderChrome(to: dir) }
        let failures = tally.failures
        if failures == 0 {
            print("Vindue-selvtest: alt OK")
        } else {
            print("Vindue-selvtest: \(failures) fejl")
        }
        return failures
    }

    /// Tegner skallen med tomt indhold, så baggrund og kant kan sammenlignes pixel for pixel.
    static func renderChrome(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "pladespiller.selftest") ?? .standard
        for (scheme, dim) in [(ColorScheme.dark, 0.0), (.light, 0.0), (.dark, 1.0)] {
            for size in WidgetSize.allCases {
                let settings = Settings(defaults: defaults)
                settings.size = size
                let presentation = WidgetPresentation()
                presentation.dimAmount = dim
                let view = WidgetChrome(content: Color.clear)
                    .environment(settings)
                    .environment(\.widgetPresentation, presentation)
                    .environment(\.colorScheme, scheme)
                let r = ImageRenderer(content: view)
                r.scale = 2
                guard let cg = r.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let url = dir.appendingPathComponent("chrome-\(scheme == .dark ? "mork" : "lys")\(dim > 0 ? "-daempet" : "")-\(size.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("     skrev", url.path)
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: "pladespiller.selftest")
    }
}
