import Foundation

/// Tidsindstillet sangtekst (fra LRCLIB). Ejes (hentning/parsning) af Musikdata-agenten; Grafik viser den.
struct Lyrics: Equatable {
    struct Word: Equatable {
        var start: TimeInterval
        var text: String
    }
    struct Line: Equatable {
        /// Sekunder fra sangens start.
        var start: TimeInterval
        var text: String
        /// Ord-timing hvis kilden har den ("enhanced LRC"), ellers tom.
        var words: [Word] = []
        /// Tom linje i LRC = instrumentalt stykke.
        var isInstrumental: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Den sang teksten hører til (`NowPlaying.trackKey`).
    var trackKey: String
    var lines: [Line]
    /// Hele sangen er instrumental (LRCLIB `instrumental: true`).
    var instrumental = false

    /// Indeks for linjen der synges ved `position`, eller nil før første linje.
    func lineIndex(at position: TimeInterval) -> Int? {
        lines.lastIndex { $0.start <= position }
    }
}

enum LyricsState: Equatable {
    case off           // slået fra i indstillinger, eller intet spiller
    case loading
    case found(Lyrics)
    case notFound      // vis titel + kunstner i stedet
}
