import AppKit

/// Tekster og kildeapp-oplysninger til visning (med pæne reserver, QA K6).
enum TrackStrings {
    static func title(_ np: NowPlaying) -> String {
        let t = np.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Ukendt titel" : t
    }

    static func artist(_ np: NowPlaying) -> String {
        let a = np.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return SourceApp.name(for: np.sourceAppBundleID) ?? "Ukendt kunstner"
    }

    static func album(_ np: NowPlaying) -> String? {
        let a = np.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? nil : a
    }
}

/// Navn og ikon for kildeappen ud fra bundle-id. Slås op én gang pr. app og caches.
enum SourceApp {
    private static var icons: [String: NSImage] = [:]
    private static var missing: Set<String> = []
    private static var names: [String: String] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let hit = icons[bundleID] { return hit }
        if missing.contains(bundleID) { return nil }
        guard let url = url(for: bundleID) else { missing.insert(bundleID); return nil }
        // Tegnes om til et lille, almindeligt sRGB-bitmap: systemikonet har mange repræsentationer og et bredt
        // farverum, som ellers får hele SwiftUI-billedet tegnet i et andet farverum (vasket ud i snapshots).
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let px = 64
        guard let cg = Drawing.image(size: CGSize(width: px, height: px), scale: 1, { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            source.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
        }) else { missing.insert(bundleID); return nil }
        let icon = NSImage(cgImage: cg, size: NSSize(width: 32, height: 32))
        icons[bundleID] = icon
        return icon
    }

    static func name(for bundleID: String) -> String? {
        if let hit = names[bundleID] { return hit }
        let known: [String: String] = [NowPlaying.BundleID.spotify: "Spotify", NowPlaying.BundleID.music: "Musik"]
        if let k = known[bundleID] { names[bundleID] = k; return k }
        guard let url = url(for: bundleID) else { return nil }
        let n = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        names[bundleID] = n
        return n
    }
}
