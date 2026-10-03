import AppKit
import Observation
import SwiftUI

/// Hvordan Apples widgets ser ud lige nu, aflæst fra systemets indstillinger. Ingen polling:
/// opdateres på distribuerede notifikationer og KVO på de relevante nøgler.
///
/// - `AppleIconAppearanceTheme` (globalt domæne) = Systemindstillinger ▸ Udseende ▸
///   "Ikon- og widgetstil": `Regular…` (Standard/Mørk), `Clear…` (Klar), `Tinted…` (Tonet),
///   med endelsen `Light`/`Dark` (fast) eller ingen/`Automatic` (følger systemet).
///   Hos brugeren: `RegularDark` → widgets er mørke og uigennemsigtige selv i lys tilstand.
/// - `com.apple.widgets widgetAppearance` = Skrivebord og Dock ▸ "Widgetstil"
///   (Automatisk / Monokrom / Fuld farve). Gemmes til det falmede look (senere milepæl).
@Observable
final class WidgetStyle {
    enum Material: Equatable {
        /// Standard/Mørk: uigennemsigtig flade (det brugeren har nu).
        case opaque
        /// Klar/Tonet: Liquid Glass.
        case glass
    }

    private(set) var material: Material = .opaque
    /// `nil` = følg systemets lyse/mørke tilstand.
    private(set) var forcedScheme: ColorScheme?
    private(set) var iconTheme: String?
    private(set) var widgetAppearance: Int?

    /// Den NSAppearance panelet skal have (nil = følg systemet).
    var nsAppearance: NSAppearance? {
        switch forcedScheme {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        default: nil
        }
    }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var kvo: DefaultsObserver?

    init() {
        reload()
        let dnc = DistributedNotificationCenter.default()
        for name in ["AppleInterfaceThemeChangedNotification",
                     "AppleIconAppearanceThemeChangedNotification",
                     "com.apple.widgets.appearanceChanged"] {
            observers.append(dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        kvo = DefaultsObserver(keys: ["AppleIconAppearanceTheme", "AppleInterfaceStyle"]) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        CFPreferencesAppSynchronize("com.apple.widgets" as CFString)
        let theme = CFPreferencesCopyAppValue("AppleIconAppearanceTheme" as CFString,
                                              kCFPreferencesAnyApplication) as? String
        let appearance = (CFPreferencesCopyAppValue("widgetAppearance" as CFString,
                                                    "com.apple.widgets" as CFString) as? NSNumber)?.intValue
        let parsed = Self.parse(iconTheme: theme)
        if iconTheme != theme { iconTheme = theme }
        if widgetAppearance != appearance { widgetAppearance = appearance }
        if material != parsed.material { material = parsed.material }
        if forcedScheme != parsed.scheme { forcedScheme = parsed.scheme }
    }

    /// Ren funktion: `RegularDark` → (.opaque, .dark), `ClearAutomatic` → (.glass, nil) osv.
    nonisolated static func parse(iconTheme: String?) -> (material: Material, scheme: ColorScheme?) {
        guard let t = iconTheme?.lowercased() else { return (.opaque, nil) }
        let material: Material = (t.hasPrefix("clear") || t.hasPrefix("tinted")) ? .glass : .opaque
        let scheme: ColorScheme? = t.hasSuffix("dark") ? .dark : t.hasSuffix("light") ? .light : nil
        return (material, scheme)
    }
}

/// KVO på UserDefaults.standard (som også ser det globale domæne).
private final class DefaultsObserver: NSObject {
    private let keys: [String]
    private let onChange: @MainActor () -> Void

    init(keys: [String], onChange: @escaping @MainActor () -> Void) {
        self.keys = keys
        self.onChange = onChange
        super.init()
        for k in keys { UserDefaults.standard.addObserver(self, forKeyPath: k, options: [], context: nil) }
    }

    deinit {
        for k in keys { UserDefaults.standard.removeObserver(self, forKeyPath: k) }
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let cb = onChange
        Task { @MainActor in cb() }
    }
}
