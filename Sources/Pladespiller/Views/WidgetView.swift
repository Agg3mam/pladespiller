import SwiftUI

/// Indholdet i widgetten for lille/mellem/stor. Ejes af Grafik-agenten.
/// Bølge 0: pladsholder.
struct WidgetView: View {
    @Environment(Settings.self) private var settings
    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "record.circle")
                .font(.system(size: 40, weight: .light))
            Text(store.current?.title ?? "Intet spiller")
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
