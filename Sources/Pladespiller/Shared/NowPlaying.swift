import AppKit

/// Det der spiller lige nu. Fælles model for alle kilder (Spotify, Musik, test, senere MediaRemote).
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var duration: TimeInterval
    var position: TimeInterval
    var positionTimestamp: Date   // tidspunktet hvor position blev målt
    var isPlaying: Bool
    var sourceAppBundleID: String // fx com.spotify.client

    /// Identificerer sangen uafhængigt af afspilningstilstand. Ændrer sig, når der kommer en ny sang.
    var trackKey: String { "\(sourceAppBundleID)|\(title)|\(artist)|\(album)" }

    /// Positionen udregnet lokalt: `position + (nu - positionTimestamp)` mens der spilles.
    func position(at date: Date = .now) -> TimeInterval {
        var p = position
        if isPlaying { p += date.timeIntervalSince(positionTimestamp) }
        if duration > 0 { p = min(p, duration) }
        return max(0, p)
    }

    /// Fremdrift 0...1 (0 hvis varigheden er ukendt).
    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return position(at: date) / duration
    }
}

extension NowPlaying {
    /// Kendte kilde-apps.
    enum BundleID {
        static let spotify = "com.spotify.client"
        static let music = "com.apple.Music"
        static let mock = "dk.holgerskov.Pladespiller.mock"
    }
}

/// Formaterer sekunder som `1:42`.
func formatTime(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
