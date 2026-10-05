import Foundation
import Observation

enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Lille"
        case .medium: "Mellem"
        case .large: "Stor"
        }
    }
}

enum TurntableTheme: String, CaseIterable, Identifiable {
    case flat, wood, aluminium, black, auto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: "Flad"
        case .wood: "Træ"
        case .aluminium: "Aluminium"
        case .black: "Sort"
        case .auto: "Auto"
        }
    }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case automatic, alwaysFull, alwaysDimmed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatisk"
        case .alwaysFull: "Altid fuld farve"
        case .alwaysDimmed: "Altid dæmpet"
        }
    }
}

/// Hvor hurtigt pladen drejer.
enum SpinSpeed: String, CaseIterable, Identifiable {
    case slow, calm, rpm33, rpm45
    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: "Langsom"
        case .calm: "Rolig"
        case .rpm33: "33⅓ o/min (ægte)"
        case .rpm45: "45 o/min"
        }
    }
    /// Sekunder pr. omgang.
    var secondsPerRevolution: TimeInterval {
        switch self {
        case .slow: 3.0          // 20 o/min
        case .calm: 2.25         // ≈27 o/min
        case .rpm33: 1.8         // 33⅓ o/min
        case .rpm45: 60.0 / 45   // 45 o/min
        }
    }
    /// Hvilken af kroppens to knapper der lyser (33 eller 45).
    var isFortyFive: Bool { self == .rpm45 }
}

/// Farven på det flade tema: krop i farven, pladen en lys gennemskinnelig udgave af den.
enum FlatColor: String, CaseIterable, Identifiable {
    case auto, yellow, orange, red, pink, purple, blue, teal, green, black, white, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto (fra coveret)"
        case .yellow: "Gul"
        case .orange: "Orange"
        case .red: "Rød"
        case .pink: "Pink"
        case .purple: "Lilla"
        case .blue: "Blå"
        case .teal: "Turkis"
        case .green: "Grøn"
        case .black: "Sort"
        case .white: "Hvid"
        case .custom: "Vælg farve…"
        }
    }
    /// sRGB-hex for de faste farver. Nil for `.auto` (fra coveret) og `.custom` (se `Settings.flatCustomHex`).
    var hex: String? {
        switch self {
        case .yellow: "F2B705"   // målt på brugerens referencebillede
        case .orange: "F27405"
        case .red: "D9352B"
        case .pink: "E8789C"
        case .purple: "7B4FC9"
        case .blue: "2F6FD6"
        case .teal: "1F9E95"
        case .green: "3E9B4F"
        case .black: "1C1C1E"
        case .white: "F2F0EB"
        case .auto, .custom: nil
        }
    }
}

/// Alle brugerindstillinger, gemt i UserDefaults. "Åbn ved login" gemmes ikke her:
/// sandheden er `SMAppService.mainApp.status`.
@Observable
final class Settings {
    enum Key {
        static let size = "pladespiller.size"
        static let theme = "pladespiller.theme"
        static let colorMode = "pladespiller.colorMode"
        static let positionLocked = "pladespiller.positionLocked"
        static let spinSpeed = "pladespiller.spinSpeed"
        static let flatColor = "pladespiller.flatColor"
        static let flatCustomHex = "pladespiller.flatCustomHex"
        static let showControls = "pladespiller.showControls"
        static let showLyrics = "pladespiller.showLyrics"
        /// Skærmen widgetten sidst stod på (stabilt skærm-id).
        static let lastScreenID = "pladespiller.lastScreenID"
        /// Placering pr. skærm: `placement.<skærm-id>` → `"x,y"` (vinduets øverste venstre hjørne, AppKit-skærmkoordinater).
        static func placement(screenID: String) -> String { "pladespiller.placement.\(screenID)" }
    }

    enum Default {
        static let size: WidgetSize = .medium
        static let theme: TurntableTheme = .flat   // brugerens valg 2026-10-05
        static let flatColor: FlatColor = .auto
        static let flatCustomHex = "F2B705"
        /// Brugeren vil have pladespilleren "stor og alene": ingen knapper/fremdrift som standard.
        static let showControls = false
        static let showLyrics = true
        static let colorMode: ColorMode = .automatic
        static let positionLocked = false
        static let spinSpeed: SpinSpeed = .calm
    }

    @ObservationIgnored private let defaults: UserDefaults

    var size: WidgetSize { didSet { defaults.set(size.rawValue, forKey: Key.size) } }
    var theme: TurntableTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    var colorMode: ColorMode { didSet { defaults.set(colorMode.rawValue, forKey: Key.colorMode) } }
    var positionLocked: Bool { didSet { defaults.set(positionLocked, forKey: Key.positionLocked) } }
    var spinSpeed: SpinSpeed { didSet { defaults.set(spinSpeed.rawValue, forKey: Key.spinSpeed) } }
    var flatColor: FlatColor { didSet { defaults.set(flatColor.rawValue, forKey: Key.flatColor) } }
    /// sRGB-hex uden "#", bruges når `flatColor == .custom`.
    var flatCustomHex: String { didSet { defaults.set(flatCustomHex, forKey: Key.flatCustomHex) } }
    /// Vis titel/kunstner-kolonne, knapper og fremdriftslinje. Fra = kun pladespilleren (+ evt. sangtekst).
    var showControls: Bool { didSet { defaults.set(showControls, forKey: Key.showControls) } }
    /// Vis sangtekst i hjørnet (henter fra LRCLIB). Uden sangtekst vises titel + kunstner i hjørnet.
    var showLyrics: Bool { didSet { defaults.set(showLyrics, forKey: Key.showLyrics) } }
    var lastScreenID: String? { didSet { defaults.set(lastScreenID, forKey: Key.lastScreenID) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        size = defaults.string(forKey: Key.size).flatMap(WidgetSize.init) ?? Default.size
        theme = defaults.string(forKey: Key.theme).flatMap(TurntableTheme.init) ?? Default.theme
        colorMode = defaults.string(forKey: Key.colorMode).flatMap(ColorMode.init) ?? Default.colorMode
        positionLocked = defaults.object(forKey: Key.positionLocked) as? Bool ?? Default.positionLocked
        spinSpeed = defaults.string(forKey: Key.spinSpeed).flatMap(SpinSpeed.init) ?? Default.spinSpeed
        flatColor = defaults.string(forKey: Key.flatColor).flatMap(FlatColor.init) ?? Default.flatColor
        flatCustomHex = defaults.string(forKey: Key.flatCustomHex) ?? Default.flatCustomHex
        showControls = defaults.object(forKey: Key.showControls) as? Bool ?? Default.showControls
        showLyrics = defaults.object(forKey: Key.showLyrics) as? Bool ?? Default.showLyrics
        lastScreenID = defaults.string(forKey: Key.lastScreenID)
    }

    func savedOrigin(screenID: String) -> CGPoint? {
        guard let s = defaults.string(forKey: Key.placement(screenID: screenID)) else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    func saveOrigin(_ origin: CGPoint, screenID: String) {
        defaults.set("\(origin.x),\(origin.y)", forKey: Key.placement(screenID: screenID))
    }
}
