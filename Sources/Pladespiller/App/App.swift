import AppKit
import ServiceManagement
import SwiftUI

/// Opstart. Ejes af hovedagenten.
///
/// Kommandolinje:
///   --mock                    brug testdata (scriptet løkke) i stedet for Spotify/Musik
///   --render-snapshots <dir>  tegn visninger til PNG og afslut (Grafik-agenten)
///   --nowplaying-log          log det der spiller og afslut aldrig (Musikdata-agenten)
///   --unregister-login-item   meld "Åbn ved login" fra og afslut (scripts/uninstall.sh)
///   --window-selftest [dir]   tjek gitter/placering og tegn skallen til PNG (Vindue-agenten)
@main
enum PladespillerMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
        let mock = args.contains("--mock") || ProcessInfo.processInfo.environment["PLADESPILLER_MOCK"] == "1"

        if let i = args.firstIndex(of: "--render-snapshots") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : "snapshots"
            SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: dir))
            exit(0)
        }
        if args.contains("--nowplaying-log") {
            NowPlayingDebugCLI.run(mock: mock)
        }
        if let i = args.firstIndex(of: "--window-selftest") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : nil
            exit(Int32(WindowSelfTest.run(outputDirectory: dir.map { URL(fileURLWithPath: $0) })))
        }

        // Kun én kopi ad gangen.
        let me = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0 != me && !$0.isTerminated && $0.processIdentifier < me.processIdentifier
           }) {
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(mock: mock)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    let store: NowPlayingStore
    private var panel: WidgetPanelController?

    init(mock: Bool) {
        store = NowPlayingStore(sources: mock ? [MockNowPlayingSource()] : NowPlayingStore.defaultSources())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        let settings = settings, store = store
        let panel = WidgetPanelController(settings: settings) {
            WidgetView()
                .environment(settings)
                .environment(store)
        }
        panel.show()
        self.panel = panel
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
