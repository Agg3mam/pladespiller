import CoreServices
import Foundation

/// Apple Events sendt direkte til en **kørende proces (pid)**, ikke via AppleScript.
///
/// Hvorfor: `tell application id "…"` adresserer appen via LaunchServices, og hvis appen lukker
/// mellem `is running` og et af scriptets kald (et status-script sender ~8 events), starter macOS
/// den igen. En pid-adresse (`NSAppleEventDescriptor(processIdentifier:)`) kan aldrig starte noget:
/// er processen væk, fejler kaldet med -600/-609. Samme adresse bruges til at spørge TCC om
/// tilladelsen (`AEDeterminePermissionToAutomateTarget`) uden at vise et vindue.
///
/// Alle kald kører på én seriel kø (samme kø som AppleScript-reserven), aldrig på main thread.
nonisolated struct AETarget: @unchecked Sendable {   // oprettes og bruges kun på køen
    let pid: pid_t
    let address: NSAppleEventDescriptor
    /// Sekunder pr. event. Status/kommandoer: 2 s (og en timeout afbryder resten af statuskaldet,
    /// så en hængende app højst holder køen ~2 s). Cover: 5 s.
    var timeout: TimeInterval = 2

    init(pid: pid_t) {
        self.pid = pid
        address = NSAppleEventDescriptor(processIdentifier: pid)
    }

    /// Sender et event og returnerer svarets direkte objekt.
    @discardableResult
    func send(_ eventClass: String, _ eventID: String, direct: NSAppleEventDescriptor? = nil,
              params: [(String, NSAppleEventDescriptor)] = []) throws(ScriptError) -> ScriptValue {
        let event = NSAppleEventDescriptor(eventClass: AE.fcc(eventClass), eventID: AE.fcc(eventID),
                                           targetDescriptor: address, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: AE.fcc("----")) }
        for (k, v) in params { event.setParam(v, forKeyword: AE.fcc(k)) }
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply], timeout: timeout)
        } catch {
            let ns = error as NSError
            throw ScriptError(number: ns.code, message: ns.localizedDescription)
        }
        if let errn = reply.paramDescriptor(forKeyword: AE.fcc("errn")), errn.int32Value != 0 {
            let msg = reply.paramDescriptor(forKeyword: AE.fcc("errs"))?.stringValue ?? "fejl i appen"
            throw ScriptError(number: Int(errn.int32Value), message: msg)
        }
        guard let result = reply.paramDescriptor(forKeyword: AE.fcc("----")) else { return .missing }
        return AE.value(from: result)
    }

    /// `get <specifier>`.
    func get(_ spec: NSAppleEventDescriptor) throws(ScriptError) -> ScriptValue {
        try send("core", "getd", direct: spec)
    }

    /// `get`, men en fejl i selve egenskaben (fx -1728 "findes ikke") giver `fallback`.
    /// Tilladelse, forsvundet app og timeout kastes videre.
    func get(_ spec: NSAppleEventDescriptor, or fallback: ScriptValue) throws(ScriptError) -> ScriptValue {
        do { return try get(spec) } catch {
            if error.isNotAuthorized || error.isAppGone || error.isTimeout || error.needsConsent { throw error }
            return fallback
        }
    }

    /// `count <klasse> of <container>`.
    func count(_ elementClass: String, in container: NSAppleEventDescriptor) throws(ScriptError) -> Int {
        Int(try send("core", "cnte", direct: container, params: [("kocl", NSAppleEventDescriptor(typeCode: AE.fcc(elementClass)))]).double ?? 0)
    }

    /// TCC-tilladelse til at sende Apple Events til processen. `ask: false` viser aldrig et vindue.
    func permission(ask: Bool) -> AccessState {
        guard let desc = address.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        return AccessState(status: status)
    }
}

/// Svar fra `AEDeterminePermissionToAutomateTarget`.
nonisolated enum AccessState: Equatable, Sendable {
    case granted
    case denied            // -1743
    case notDetermined     // -1744: macOS har ikke spurgt endnu
    case notRunning        // -600
    case unknown(Int32)

    init(status: OSStatus) {
        switch status {
        case noErr: self = .granted
        case -1743: self = .denied
        case -1744: self = .notDetermined
        case -600, -609: self = .notRunning
        default: self = .unknown(status)
        }
    }
}

/// Byggesten til object specifiers (samme struktur som AppleScript selv bygger; se selvtesten).
nonisolated enum AE {
    /// Appen selv (rod for alle specifiers).
    static var app: NSAppleEventDescriptor { .null() }

    /// `<egenskab> of <container>`, fx `prop("pPlS")` = player state.
    static func prop(_ code: String, of container: NSAppleEventDescriptor = app) -> NSAppleEventDescriptor {
        specifier(want: NSAppleEventDescriptor(typeCode: fcc("prop")), form: "prop",
                  seld: NSAppleEventDescriptor(typeCode: fcc(code)), from: container)
    }

    /// `<klasse> <n> of <container>`, fx `element("cArt", 1, of: track)` = artwork 1 of track.
    static func element(_ cls: String, _ index: Int32, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: NSAppleEventDescriptor(typeCode: fcc(cls)), form: "indx",
                  seld: NSAppleEventDescriptor(int32: index), from: container)
    }

    private static func specifier(want: NSAppleEventDescriptor, form: String, seld: NSAppleEventDescriptor,
                                  from: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let rec = NSAppleEventDescriptor.record()
        rec.setDescriptor(want, forKeyword: fcc("want"))
        rec.setDescriptor(NSAppleEventDescriptor(enumCode: fcc(form)), forKeyword: fcc("form"))
        rec.setDescriptor(seld, forKeyword: fcc("seld"))
        rec.setDescriptor(from, forKeyword: fcc("from"))
        return rec.coerce(toDescriptorType: fcc("obj ")) ?? rec
    }

    static func fcc(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func fourCCString(_ c: FourCharCode) -> String {
        String(bytes: [UInt8(c >> 24 & 0xFF), UInt8(c >> 16 & 0xFF), UInt8(c >> 8 & 0xFF), UInt8(c & 0xFF)], encoding: .macOSRoman) ?? "????"
    }

    /// Oversætter en NSAppleEventDescriptor til `ScriptValue`.
    static func value(from d: NSAppleEventDescriptor) -> ScriptValue {
        switch d.descriptorType {
        case fcc("list"):
            guard d.numberOfItems > 0 else { return .list([]) }
            return .list((1...d.numberOfItems).map { i in d.atIndex(i).map(value(from:)) ?? .missing })
        case fcc("utxt"), fcc("utf8"), fcc("TEXT"):
            return .text(d.stringValue ?? "")
        case fcc("long"), fcc("shor"), fcc("comp"), fcc("doub"), fcc("sing"), fcc("magn"), fcc("ucom"), fcc("exte"):
            return .number(d.doubleValue)
        case fcc("true"): return .bool(true)
        case fcc("fals"): return .bool(false)
        case fcc("bool"): return .bool(d.booleanValue)
        case fcc("null"): return .missing
        case fcc("type"):
            return d.typeCodeValue == fcc("msng") ? .missing : .text(fourCCString(d.typeCodeValue))
        case fcc("enum"):
            // Rå kode, fx "kPSP" (playing). `PlayerStatus.state(from:)` kender kodene.
            return .text(fourCCString(d.enumCodeValue))
        default:
            // Fx cover-data ('tdta', 'JPEG', 'PNGf', 'PICT').
            return .data(d.data)
        }
    }
}

/// En seriel kø til Apple Events for ÉN kildeapp. Hver kilde har sin egen, så en Spotify der hænger
/// (op til `AETarget.timeout` pr. event) ikke blokerer Musik og omvendt.
/// Tilladelsesdialogen (ask: true) kører IKKE her, men på `permission(pid:ask:)`, så status og
/// kommandoer ikke venter på at brugeren svarer.
nonisolated final class AppleEventQueue: Sendable {
    let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: "dk.holgerskov.Pladespiller.appleevents.\(label)", qos: .userInitiated)
    }

    /// Spørger TCC om tilladelse til at styre processen. Kører på en global kø (trådsikkert API),
    /// uden for kildernes event-køer. `ask: true` kan vente længe på brugeren.
    static func permission(pid: pid_t, ask: Bool) async -> AccessState {
        await withCheckedContinuation { (cont: CheckedContinuation<AccessState, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: AETarget(pid: pid).permission(ask: ask))
            }
        }
    }

    /// Kører `work` mod processen `pid` på køen og leverer resultatet tilbage (med tidspunkter).
    func run<T: Sendable>(pid: pid_t, _ work: @escaping @Sendable (AETarget) throws(ScriptError) -> T) async -> Timed<T> {
        await withCheckedContinuation { (cont: CheckedContinuation<Timed<T>, Never>) in
            queue.async {
                let started = Date()
                let result: Result<T, ScriptError>
                do throws(ScriptError) { result = .success(try work(AETarget(pid: pid))) } catch { result = .failure(error) }
                cont.resume(returning: Timed(result: result, started: started, finished: Date()))
            }
        }
    }
}

/// Et resultat med hvornår det blev hentet (til `positionTimestamp`).
nonisolated struct Timed<T: Sendable>: Sendable {
    var result: Result<T, ScriptError>
    var started: Date
    var finished: Date

    /// Bedste gæt på hvornår appen læste værdierne: midt i rundturen.
    var measuredAt: Date { started.addingTimeInterval(finished.timeIntervalSince(started) / 2) }
    var milliseconds: Int { Int((finished.timeIntervalSince(started) * 1000).rounded()) }
}
