import AppKit

/// Lille LRU-cache med de seneste covers (nøgle = url eller sang-id) og hentning via URLSession.
final class ArtworkCache {
    let capacity: Int
    private var entries: [(key: String, image: NSImage)] = []   // nyeste først
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(capacity: Int = 5) {
        self.capacity = capacity
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    var keys: [String] { entries.map(\.key) }

    func image(for key: String) -> NSImage? {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let e = entries.remove(at: i)
        entries.insert(e, at: 0)
        return e.image
    }

    func insert(_ image: NSImage, for key: String) {
        entries.removeAll { $0.key == key }
        entries.insert((key, image), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    /// Henter et billede fra en http(s)-url (fra cachen hvis muligt). Samme url hentes kun én gang ad gangen.
    func load(urlString: String) async -> NSImage? {
        if let cached = image(for: urlString) { return cached }
        if let task = inFlight[urlString] { return await task.value }
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        let session = session
        let task = Task<NSImage?, Never> {
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                return NSImage(data: data)
            } catch {
                NowPlayingLog.log("[cover] kunne ikke hente \(urlString): \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[urlString] = task
        let image = await task.value
        inFlight[urlString] = nil
        if let image { insert(image, for: urlString) }
        return image
    }
}
