import Foundation
import os

/// Fælles log for kilderne. Skriver altid til os.Logger (Konsol: undersystem dk.holgerskov.Pladespiller),
/// og til `handler` når `--nowplaying-log` kører.
enum NowPlayingLog {
    static var handler: ((String) -> Void)?
    private static let logger = Logger(subsystem: "dk.holgerskov.Pladespiller", category: "NowPlaying")

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        handler?(message)
    }
}
