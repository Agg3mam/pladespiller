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
    case wood, aluminium, black, auto
    var id: String { rawValue }
    var title: String {
        switch self {
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
        /// Skærmen widgetten sidst stod på (stabilt skærm-id).
        static let lastScreenID = "pladespiller.lastScreenID"
        /// Placering pr. skærm: `placement.<skærm-id>` → `"x,y"` (vinduets øverste venstre hjørne, AppKit-skærmkoordinater).
        static func placement(screenID: String) -> String { "pladespiller.placement.\(screenID)" }
    }

    enum Default {
        static let size: WidgetSize = .medium
        static let theme: TurntableTheme = .wood   // TODO: spørg brugeren (afsnit 7)
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
    var lastScreenID: String? { didSet { defaults.set(lastScreenID, forKey: Key.lastScreenID) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        size = defaults.string(forKey: Key.size).flatMap(WidgetSize.init) ?? Default.size
        theme = defaults.string(forKey: Key.theme).flatMap(TurntableTheme.init) ?? Default.theme
        colorMode = defaults.string(forKey: Key.colorMode).flatMap(ColorMode.init) ?? Default.colorMode
        positionLocked = defaults.object(forKey: Key.positionLocked) as? Bool ?? Default.positionLocked
        spinSpeed = defaults.string(forKey: Key.spinSpeed).flatMap(SpinSpeed.init) ?? Default.spinSpeed
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
