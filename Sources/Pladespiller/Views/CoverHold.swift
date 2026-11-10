import AppKit
import Observation

/// Ved sangskift kommer den nye sang først UDEN cover (det skal hentes), og coveret kommer et øjeblik efter.
/// Vist direkte giver det et grimt mellemtrin: det gamle cover → en tom papiretiket (og i Auto en sort krop) → det nye cover.
///
/// Hverken Spotify eller Musik fortæller, hvilken sang der kommer bagefter, så det næste cover kan ikke hentes på forhånd.
/// I stedet bliver det gamle cover liggende på pladen, indtil det nye er klar – så er der kun ét skift, direkte fra cover
/// til cover. Kommer der intet cover inden for `patience` sekunder (sangen har ikke noget), vises tekst-etiketten.
/// Titel, kunstner, arm og sangtekst skifter med det samme; kun billedet venter.
@Observable
final class CoverHold {
    static let shared = CoverHold()
    /// Slås fra i snapshots og test, hvor hver visning skal tegnes præcis som dens data siger.
    @ObservationIgnored static var enabled = true
    static let patience: TimeInterval = 2.5

    /// Tæller op, når ventetiden er gået, så visningerne tegnes igen (nu uden det gamle cover).
    private(set) var tick = 0
    @ObservationIgnored private var last: (key: String, image: NSImage)?
    @ObservationIgnored private var waiting: (key: String, since: Date)?
    @ObservationIgnored private var work: DispatchWorkItem?

    @ObservationIgnored private var lastDeck: NowPlaying?

    /// Venter vi på den nye sangs cover lige nu? (Holder også styr på, hvornår ventetiden begyndte.)
    private func holding(_ np: NowPlaying) -> Bool {
        if let art = np.artwork {
            last = (np.trackKey, art)
            waiting = nil
            work?.cancel()
            return false
        }
        guard let last, last.key != np.trackKey else { return false }
        if waiting?.key != np.trackKey {
            waiting = (np.trackKey, .now)
            work?.cancel()
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.tick += 1 }
            }
            work = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience + 0.05, execute: item)
        }
        guard let waiting else { return false }
        return Date.now.timeIntervalSince(waiting.since) < Self.patience
    }

    /// Til teksten og farverne: som `np`, men med det forrige cover, mens den nye sangs cover er på vej.
    func resolve(_ np: NowPlaying?) -> NowPlaying? {
        _ = tick
        guard Self.enabled, var np else { return np }
        if holding(np), let last { np.artwork = last.image }
        return np
    }

    /// Til selve pladespilleren: den forrige sang spiller videre på pladen, til den nye sangs cover er klar. Så sker hele
    /// pladeskiftet på én gang – armen løftes, coveret skifter, mens armen er i luften, og armen sættes ned igen –
    /// i stedet for at armen flytter sig først, og coveret skifter bagefter.
    func deck(_ np: NowPlaying?) -> NowPlaying? {
        _ = tick
        guard Self.enabled, let np else { lastDeck = nil; return np }
        if holding(np), var old = lastDeck {
            old.isPlaying = np.isPlaying          // pause/afspil følger stadig med det samme
            return old
        }
        lastDeck = np
        return np
    }
}
