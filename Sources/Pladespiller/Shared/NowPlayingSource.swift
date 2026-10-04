import Foundation

/// En kilde til "det der spiller nu". Alle kilder kører på main actor.
///
/// Regler:
/// - `start()` må aldrig åbne kilde-appen. Tjek med `NSRunningApplication`, før der sendes AppleScript.
/// - Kald `onChange` hver gang `current` ændrer sig (ny sang, afspil/pause, spring i sangen).
/// - Når appen ikke kører eller intet spiller, er `current` nil eller har `isPlaying == false`.
protocol NowPlayingSource: AnyObject {
    /// Bundle-id for appen kilden repræsenterer (fx com.spotify.client).
    var bundleID: String { get }
    /// Seneste kendte tilstand.
    var current: NowPlaying? { get }
    /// Hvornår `current` sidst ændrede sig (bruges til at vælge mellem to kilder der begge spiller).
    var lastChange: Date { get }
    /// Sættes af `NowPlayingStore`.
    var onChange: (() -> Void)? { get set }

    func start()
    func stop()

    func playPause()
    func nextTrack()
    func previousTrack()
    /// Spol til en position i sangen (sekunder). Opdatér `current` optimistisk med det samme.
    func seek(to position: TimeInterval)
}

extension NowPlayingSource {
    /// Standard: kilden kan ikke spole (fx testkilder i snapshots). Rigtige kilder implementerer den.
    func seek(to position: TimeInterval) {}
}
