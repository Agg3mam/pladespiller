import AppKit

/// Mål og designkonstanter. Målt på brugerens egne Apple-widgets (macOS 27.2, 2026-10-03):
/// - Widget-vinduer ligger på niveau -2147483601 = desktopIconWindow + 2.
/// - Vinduerne er 180/360 pt og ligger kant i kant i et 180 pt-gitter.
/// - Den synlige flade er indrykket 8 pt i vinduet (164×164, 344×164, 344×344).
/// - Hjørneradius 28 pt, continuous. Ingen synlig systemskygge.
/// - En svag lys kant (≈1 px) langs fladen.
enum WidgetMetrics {
    static let gridPitch: CGFloat = 180
    static let windowInset: CGFloat = 8
    static let cornerRadius: CGFloat = 28

    static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
    }

    static func windowSize(for size: WidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: gridPitch, height: gridPitch)
        case .medium: CGSize(width: gridPitch * 2, height: gridPitch)
        case .large: CGSize(width: gridPitch * 2, height: gridPitch * 2)
        }
    }

    static func bodySize(for size: WidgetSize) -> CGSize {
        let w = windowSize(for: size)
        return CGSize(width: w.width - windowInset * 2, height: w.height - windowInset * 2)
    }

    // Falmet look
    static let dimTransition: TimeInterval = 0.3
    /// Ved dimAmount = 1 (lineært imellem). Foreslået af Vindue-agenten; ikke målt på Apples dæmpede widgets endnu.
    static let dimContentSaturation: Double = 0
    static let dimContentOpacity: Double = 0.6
    static let dimBackgroundOpacity: Double = 0.2

    // Træk
    static let dragThreshold: CGFloat = 4
    static let snapDuration: TimeInterval = 0.28

    // Pladespiller-bevægelse
    /// Standardfart. Brugeren vælger selv i menuen: brug `settings.spinSpeed.secondsPerRevolution`.
    static let secondsPerRevolution: TimeInterval = SpinSpeed.calm.secondsPerRevolution
    static let spinUpDuration: TimeInterval = 0.8
    static let spinDownDuration: TimeInterval = 1.2
    static let trackChangeDuration: TimeInterval = 0.9    // skal være under 1 s
}
