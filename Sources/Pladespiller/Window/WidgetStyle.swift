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
///   (Automatisk / Monokrom / Fuld farve). Bruges af `WidgetDimming`; 1 = Fuld farve (udledt).
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

    @ObservationIgnored private var distributed: DistributedObserver?
    @ObservationIgnored private var kvo: [DefaultsObserver] = []

    init() {
        reload()
        // Appen er aldrig aktiv → .deliverImmediately, ellers holdes notifikationerne tilbage (QA A3).
        distributed = DistributedObserver(names: ["AppleInterfaceThemeChangedNotification",
                                                  "AppleIconAppearanceThemeChangedNotification",
                                                  "com.apple.widgets.appearanceChanged"]) { [weak self] in
            self?.reload()
        }
        kvo.append(DefaultsObserver(defaults: .standard,
                                    keys: ["AppleIconAppearanceTheme", "AppleInterfaceStyle"]) { [weak self] in
            self?.reload()
        })
        if let widgets = UserDefaults(suiteName: "com.apple.widgets") {
            kvo.append(DefaultsObserver(defaults: widgets, keys: ["widgetAppearance"]) { [weak self] in
                self?.reload()
            })
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

/// Distribuerede notifikationer med `.deliverImmediately` (selector-API'et kræver et NSObject).
final class DistributedObserver: NSObject {
    private let onChange: @MainActor () -> Void
    private let names: [String]

    init(names: [String], onChange: @escaping @MainActor () -> Void) {
        self.names = names
        self.onChange = onChange
        super.init()
        let dnc = DistributedNotificationCenter.default()
        for n in names {
            dnc.addObserver(self, selector: #selector(fired(_:)), name: Notification.Name(n),
                            object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc nonisolated private func fired(_ note: Notification) {
        let cb = onChange
        Task { @MainActor in cb() }
    }
}

/// KVO på en UserDefaults (`.standard` ser også det globale domæne).
private final class DefaultsObserver: NSObject {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let keys: [String]
    private let onChange: @MainActor () -> Void

    init(defaults: UserDefaults, keys: [String], onChange: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.onChange = onChange
        super.init()
        for k in keys { defaults.addObserver(self, forKeyPath: k, options: [], context: nil) }
    }

    deinit {
        for k in keys { defaults.removeObserver(self, forKeyPath: k) }
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let cb = onChange
        Task { @MainActor in cb() }
    }
}
