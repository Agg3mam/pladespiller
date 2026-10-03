import Foundation
import os

/// Fælles log for kilderne. Skriver altid til os.Logger (Konsol: undersystem dk.holgerskov.Pladespiller),
/// til `handler` når `--nowplaying-log` kører, og til en fil når appen startes med `--log`
/// (eller `PLADESPILLER_LOG=1`): `~/Library/Logs/Pladespiller/nowplaying.log`.
///
///     open -a Pladespiller --args --log
///     tail -f ~/Library/Logs/Pladespiller/nowplaying.log
enum NowPlayingLog {
    static var handler: ((String) -> Void)?
    private static let logger = Logger(subsystem: "dk.holgerskov.Pladespiller", category: "NowPlaying")

    static var fileLoggingEnabled: Bool {
        CommandLine.arguments.contains("--log") || ProcessInfo.processInfo.environment["PLADESPILLER_LOG"] == "1"
    }

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Pladespiller/nowplaying.log")

    private static let file: FileHandle? = {
        guard fileLoggingEnabled else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? h.seekToEnd()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let header = "\n=== Pladespiller \(version) startet \(Date()) pid \(getpid()) · \(Bundle.main.bundlePath) · "
            + (PlayerAppSource.useAppleScript ? "AppleScript-reserve" : "Apple Events til pid") + "\n"
        h.write(Data(header.utf8))
        return h
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        handler?(message)
        if let file {
            file.write(Data("\(clock.string(from: .now)) \(message)\n".utf8))
        }
    }
}
