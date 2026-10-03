import AppKit

/// Testkilde med opdigtede sange og covers tegnet i kode.
///
/// Med `scripted: true` kører den en fast løkke (34 s), så man kan se alle tilstande:
///   0 s  afspil sang A (starter 40 s inde)
///   8 s  pause
///  12 s  afspil igen
///  16 s  ny sang B (fra start)
///  24 s  ny sang C uden cover
///  30 s  intet spiller
///  34 s  forfra
/// Knapperne virker også (afspil/pause, næste, forrige).
final class MockNowPlayingSource: NowPlayingSource {
    let bundleID = NowPlaying.BundleID.mock
    private(set) var current: NowPlaying?
    private(set) var lastChange = Date.distantPast
    var onChange: (() -> Void)?

    private let scripted: Bool
    private var timer: Timer?
    private var startDate = Date()
    private var trackIndex = 0

    init(scripted: Bool = true) {
        self.scripted = scripted
    }

    func start() {
        startDate = .now
        if scripted {
            applyScript(at: 0)
            var lastStep = -1
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let t = Date.now.timeIntervalSince(self.startDate).truncatingRemainder(dividingBy: 34)
                    let step = Self.scriptSteps.lastIndex { $0 <= t } ?? 0
                    if step != lastStep { lastStep = step; self.applyScript(at: step) }
                }
            }
        } else {
            set(Self.sample(0, isPlaying: true, progress: 0.2))
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func playPause() {
        guard var np = current else { set(Self.sample(trackIndex, isPlaying: true, progress: 0)); return }
        np.position = np.position(at: .now)
        np.positionTimestamp = .now
        np.isPlaying.toggle()
        set(np)
    }

    func nextTrack() { jump(to: trackIndex + 1) }
    func previousTrack() { jump(to: trackIndex - 1) }

    // MARK: - Testdata (bruges også direkte af snapshot-renderere)

    struct Track {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let colors: (NSColor, NSColor)?
    }

    static let tracks: [Track] = [
        Track(title: "Natten over Nørrebro", artist: "Kobberkvartetten", album: "Sort Sol", duration: 238,
              colors: (NSColor(red: 0.85, green: 0.35, blue: 0.20, alpha: 1), NSColor(red: 0.20, green: 0.10, blue: 0.35, alpha: 1))),
        Track(title: "Blå time", artist: "Ida & Havet", album: "Lavvande", duration: 201,
              colors: (NSColor(red: 0.20, green: 0.55, blue: 0.80, alpha: 1), NSColor(red: 0.90, green: 0.85, blue: 0.60, alpha: 1))),
        Track(title: "En meget lang sangtitel der slet ikke kan være på én linje", artist: "Ukendt kunstner", album: "Uden cover",
              duration: 312, colors: nil),
    ]

    /// En færdig `NowPlaying` for testsang `index` med en given fremdrift (0...1).
    static func sample(_ index: Int, isPlaying: Bool, progress: Double, at date: Date = .now) -> NowPlaying {
        let i = ((index % tracks.count) + tracks.count) % tracks.count
        let t = tracks[i]
        return NowPlaying(title: t.title, artist: t.artist, album: t.album,
                          artwork: artwork(for: i), duration: t.duration,
                          position: t.duration * progress, positionTimestamp: date,
                          isPlaying: isPlaying, sourceAppBundleID: NowPlaying.BundleID.mock)
    }

    private static var artworkCache: [Int: NSImage] = [:]

    /// Testcover tegnet i kode (600×600 px bitmap). Nil for sange uden cover.
    static func artwork(for index: Int) -> NSImage? {
        guard let colors = tracks[index].colors else { return nil }
        if let cached = artworkCache[index] { return cached }
        let px = 600
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: px, height: px)
        NSGradient(starting: colors.0, ending: colors.1)?.draw(in: rect, angle: index == 0 ? 60 : -30)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 150, dy: 150).offsetBy(dx: index == 0 ? 80 : -60, dy: 40)).fill()
        NSColor.black.withAlphaComponent(0.2).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: px, height: 120)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: px, height: px))
        image.addRepresentation(rep)
        artworkCache[index] = image
        return image
    }

    // MARK: - Privat

    private static let scriptSteps: [TimeInterval] = [0, 8, 12, 16, 24, 30]

    private func applyScript(at step: Int) {
        switch step {
        case 0: trackIndex = 0; set(Self.sample(0, isPlaying: true, progress: 40 / Self.tracks[0].duration))
        case 1, 2: playPause()
        case 3: trackIndex = 1; set(Self.sample(1, isPlaying: true, progress: 0))
        case 4: trackIndex = 2; set(Self.sample(2, isPlaying: true, progress: 0))
        default: set(nil)
        }
    }

    private func jump(to index: Int) {
        trackIndex = ((index % Self.tracks.count) + Self.tracks.count) % Self.tracks.count
        set(Self.sample(trackIndex, isPlaying: true, progress: 0))
    }

    private func set(_ np: NowPlaying?) {
        current = np
        lastChange = .now
        onChange?()
    }
}
