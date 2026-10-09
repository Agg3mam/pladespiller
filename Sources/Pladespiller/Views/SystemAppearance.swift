import AppKit
import Observation

/// Om macOS står i lys eller mørk tilstand (Systemindstillinger ▸ Udseende). Bruges til armens farve i Flad:
/// hvid i lys tilstand, sort i mørk. Følger systemet med det samme via KVO på `NSApp.effectiveAppearance`
/// (appens eget udseende, ikke widgetpanelets, som kan være tvunget mørkt af widgetstilen).
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark = false
    /// Kun snapshots og test: tving lys/mørk.
    @ObservationIgnored var override: Bool? { didSet { reload() } }
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        reload()
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func reload() {
        let dark = override ?? (NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        if dark != isDark { isDark = dark }
    }
}
