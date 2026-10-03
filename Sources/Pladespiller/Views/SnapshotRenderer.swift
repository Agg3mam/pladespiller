import AppKit
import SwiftUI

/// `Pladespiller --render-snapshots <dir>`: tegner visninger med testdata til PNG uden at vise vinduet.
/// Ejes af Grafik-agenten.
enum SnapshotRenderer {
    static func run(outputDirectory: URL) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for size in WidgetSize.allCases {
            let settings = Settings(defaults: UserDefaults(suiteName: "pladespiller.snapshots")!)
            settings.size = size
            let mock = MockNowPlayingSource(scripted: false)
            let store = NowPlayingStore(sources: [mock])
            store.start()
            let body = WidgetMetrics.bodySize(for: size)
            let view = WidgetView()
                .frame(width: body.width, height: body.height)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
                .environment(settings)
                .environment(store)
            write(view, to: outputDirectory.appendingPathComponent("widget-\(size.rawValue).png"))
        }
    }

    static func write(_ view: some View, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("Kunne ikke tegne \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("Skrev \(url.path)")
    }
}
