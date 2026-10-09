import SwiftUI

/// Indholdet i fuld skærm (`settings.fullscreenLayout`). Ejes af Grafik-agenten. Pladsholder.
struct FullscreenView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        Text(store.current?.title ?? "Intet spiller")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}
