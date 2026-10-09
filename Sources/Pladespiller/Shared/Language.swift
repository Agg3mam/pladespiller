import Foundation
import Observation

/// Appens sprog (menu ▸ Sprog). Dansk er standard; "Automatisk" følger Macens foretrukne sprog
/// (dansk hvis det står først, ellers engelsk).
enum LanguageChoice: String, CaseIterable, Identifiable {
    case danish, english, automatic
    var id: String { rawValue }
    /// Hvert sprog står på sit eget sprog, så man altid kan finde tilbage.
    var title: String {
        switch self {
        case .danish: "Dansk"
        case .english: "English"
        case .automatic: L("Automatisk (som Macen)", "Automatic (same as Mac)")
        }
    }
}

/// Det valgte sprog. Observerbart, så SwiftUI-visninger, der kalder `L(…)`, tegnes om med det samme ved skift.
@Observable
final class AppLanguage {
    static let shared = AppLanguage()
    static let key = "pladespiller.language"

    var choice: LanguageChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key) }
    }

    var isEnglish: Bool {
        switch choice {
        case .danish: false
        case .english: true
        case .automatic: !(Locale.preferredLanguages.first?.lowercased().hasPrefix("da") ?? false)
        }
    }

    private init() {
        choice = UserDefaults.standard.string(forKey: Self.key).flatMap(LanguageChoice.init) ?? .danish
    }
}

/// Tekst på det valgte sprog: `L("Intet spiller", "Nothing playing")`.
func L(_ danish: String, _ english: String) -> String {
    AppLanguage.shared.isEnglish ? english : danish
}
