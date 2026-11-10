import AppKit
import ServiceManagement
import SwiftUI

/// Opstart. Ejes af hovedagenten.
///
/// Kommandolinje:
///   --mock                    brug testdata (scriptet løkke) i stedet for Spotify/Musik
///   --render-snapshots <dir>  tegn visninger til PNG og afslut (Grafik-agenten)
///   --nowplaying-log          log det der spiller og afslut aldrig (Musikdata-agenten)
///   --lyrics "Titel" "Kunstner" [sek]  hent sangtekst fra LRCLIB og print den
///   --unregister-login-item   meld "Åbn ved login" fra og afslut (scripts/uninstall.sh)
///   --window-selftest [dir]   tjek gitter/placering og tegn skallen til PNG (Vindue-agenten)
///   --render-arm <fil.png>    tegn et nærbillede af den realistiske arm og afslut
///   --arm-test [dir]          grib/træk i armen med syntetiske musehændelser og mål animationen (Grafik-agenten)
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
        if let i = args.firstIndex(of: "--render-arm"), args.indices.contains(i + 1) {
            // Nærbillede af den realistiske arm (stor widget, træ, 4x) – hurtigt at se på, når armens model ændres.
            let g = TurntableGeometry(size: CGSize(width: 344, height: 344), cornerRadius: 28, deck: nil, flat: false)
            var pose = TurntablePose()
            pose.armAngle = Double(g.armAngle(forProgress: 0.45))
            pose.idle = 0
            let style = TurntableStyle.make(theme: .wood, artwork: nil)
            if let cg = TurntableLayer.snapshot(g, style: style, scale: 4, pose: pose) {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--arm-test") {
            let dir = args.indices.contains(i + 1) ? URL(fileURLWithPath: args[i + 1]) : nil
            if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            _ = NSApplication.shared
            let result = ArmDragTest.run(dir: dir)
            print(result.lines.joined(separator: "\n"))
            exit(result.failures == 0 ? 0 : 1)
        }
        if args.contains("--nowplaying-log") || args.contains("--lyrics") {
            NowPlayingDebugCLI.run(mock: mock)
        }
        if let i = args.firstIndex(of: "--window-selftest") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : nil
            exit(Int32(WindowSelfTest.run(outputDirectory: dir.map { URL(fileURLWithPath: $0) })))
        }

        // Kun én kopi ad gangen. Er en ældre kopi ved at lukke (fx under build.sh --install),
        // venter vi op til 2 s på den i stedet for at lukke os selv.
        if let id = Bundle.main.bundleIdentifier {
            let me = NSRunningApplication.current
            func olderCopies() -> [NSRunningApplication] {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).filter {
                    $0 != me && !$0.isTerminated && $0.processIdentifier < me.processIdentifier
                }
            }
            let deadline = Date.now.addingTimeInterval(2)
            while !olderCopies().isEmpty, Date.now < deadline {
                RunLoop.current.run(until: .now.addingTimeInterval(0.1))
            }
            if !olderCopies().isEmpty { exit(0) }
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
    /// Ikonet i menulinjen med indstillingerne.
    private var statusItem: StatusItemController?
    /// Pladespilleren som almindeligt vindue.
    private var playerWindow: PlayerWindowController?
    /// Sne på skrivebordet i julestemningen.
    private var desktopSnow: DesktopSnowController?

    init(mock: Bool) {
        store = NowPlayingStore(sources: mock ? [MockNowPlayingSource()] : NowPlayingStore.defaultSources())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        store.lyricsEnabled = settings.showLyrics
        observeLyricsSetting()
        let settings = settings, store = store
        let fullscreen = FullscreenController(settings: settings) {
            FullscreenView()
                .environment(settings)
                .environment(store)
        }
        fullscreen.observePlaying { store.current?.isPlaying ?? false }
        let panel = WidgetPanelController(settings: settings) {
            WidgetView()
                .environment(settings)
                .environment(store)
        }
        panel.fullscreen = fullscreen
        let playerWindow = PlayerWindowController {
            FullscreenView(visibility: .playerWindow)
                .environment(settings)
                .environment(store)
        }
        panel.playerWindow = playerWindow
        self.playerWindow = playerWindow
        panel.show()
        self.panel = panel
        statusItem = StatusItemController(settings: settings, fullscreen: fullscreen, playerWindow: playerWindow)
        desktopSnow = DesktopSnowController(settings: settings)
        // `--fullscreen`: åbn fuld skærm ved start (til gennemsyn og test uden at klikke i menuen).
        if CommandLine.arguments.contains("--fullscreen") { fullscreen.show() } else { fullscreen.restoreIfNeeded() }
        // `--window`: åbn pladespilleren som vindue ved start (til gennemsyn og test).
        if CommandLine.arguments.contains("--window") { playerWindow.show() } else { playerWindow.restoreIfNeeded() }
    }

    /// Hold storens sangtekst-hentning i takt med menuvalget "Vis sangtekst".
    private func observeLyricsSetting() {
        withObservationTracking { _ = settings.showLyrics } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.store.lyricsEnabled = self.settings.showLyrics
                self.observeLyricsSetting()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
