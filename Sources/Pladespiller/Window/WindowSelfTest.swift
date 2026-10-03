import AppKit
import SwiftUI

/// `--window-selftest [mappe]`: tester gitterlogik og stil-aflæsning uden vindue og tegner
/// skallen (lys/mørk, alle størrelser) til PNG i `mappe`, så den kan sammenlignes med Apples
/// widget-billeder. Returnerer antal fejl.
enum WindowSelfTest {
    @discardableResult
    static func run(outputDirectory: URL? = nil) -> Int {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print(ok ? "OK   " : "FEJL ", name, ok ? "" : detail())
            if !ok { failures += 1 }
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

        // 9. Falmet look.
        typealias D = WidgetDimming
        check("Fuld farve-stil → aldrig dæmpet", D.target(mode: .automatic, policy: .fullColor, desktopFocused: false) == 0)
        check("Automatisk, andet program aktivt → dæmpet", D.target(mode: .automatic, policy: .automatic, desktopFocused: false) == 1)
        check("Automatisk, skrivebord i fokus → fuld farve", D.target(mode: .automatic, policy: .automatic, desktopFocused: true) == 0)
        check("Altid dæmpet", D.target(mode: .alwaysDimmed, policy: .fullColor, desktopFocused: true) == 1)
        check("Altid fuld farve", D.target(mode: .alwaysFull, policy: .automatic, desktopFocused: false) == 0)
        check("widgetAppearance 1 = Fuld farve", D.systemPolicy(widgetAppearance: 1) == .fullColor)
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
            check("menupunkter", titles == ["Lille", "Mellem", "Stor", "—", "Tema", "Farver", "—",
                                            "Lås placering", "Åbn ved login", "—", "Fjern widget"], "\(titles)")
            check("flueben ved Stor", menu.item(withTitle: "Stor")?.state == .on && menu.item(withTitle: "Lille")?.state == .off)
            let tema = menu.item(withTitle: "Tema")?.submenu
            check("Tema-undermenu", tema?.items.map(\.title) == ["Træ", "Aluminium", "Sort", "Auto"]
                  && tema?.item(withTitle: "Sort")?.state == .on)
            check("Farver-undermenu", menu.item(withTitle: "Farver")?.submenu?.items.map(\.title)
                  == ["Automatisk", "Altid fuld farve", "Altid dæmpet"])
            // Vælg "Lille" og "Aluminium" via menuens egne handlinger.
            if let i = menu.item(withTitle: "Lille") , let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) }
            if let i = tema?.item(withTitle: "Aluminium") , let a = i.action { _ = (i.target as? NSObject)?.perform(a, with: i) }
            check("menuhandling sætter indstillinger", settings.size == .small && settings.theme == .aluminium)
            withExtendedLifetime(builder) {}
            UserDefaults.standard.removePersistentDomain(forName: "pladespiller.selftest.menu")
        }

        let live = WidgetStyle()
        print("     system: AppleIconAppearanceTheme=\(live.iconTheme ?? "–") widgetAppearance=\(live.widgetAppearance.map(String.init) ?? "–") → \(live.material), \(String(describing: live.forcedScheme))")
        print("     Apple-widgets nu:", AppleWidgetWindows.frames())

        if let dir = outputDirectory { renderChrome(to: dir) }
        print(failures == 0 ? "Vindue-selvtest: alt OK" : "Vindue-selvtest: \(failures) fejl")
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
