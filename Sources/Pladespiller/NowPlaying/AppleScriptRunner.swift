import Foundation

/// Resultatet af et AppleScript, oversat til en `Sendable` værdi, så det kan sendes fra
/// AppleScript-køen tilbage til main actor (og så parsning kan testes med eksempeldata).
enum ScriptValue: Sendable, Equatable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case list([ScriptValue])
    case missing

    /// Tekst (tal skrives uden decimaler, hvis de er hele). `missing` giver nil.
    var string: String? {
        switch self {
        case .text(let s): return s
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// Tal. Tekst parses også (accepterer både "3.5" og "3,5" og "2.38E+5").
    var double: Double? {
        switch self {
        case .number(let d): return d
        case .text(let s): return Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    var items: [ScriptValue] {
        if case .list(let l) = self { return l }
        return [self]
    }

    subscript(_ i: Int) -> ScriptValue {
        let l = items
        return l.indices.contains(i) ? l[i] : .missing
    }
}

/// Fejl fra NSAppleScript.
struct ScriptError: Error, Sendable, CustomStringConvertible {
    var number: Int
    var message: String

    /// -1743: brugeren har ikke givet lov (Automatisering).
    var isNotAuthorized: Bool { number == -1743 }
    /// -600/-609: appen kører ikke / forbindelsen er væk (fx lukket lige før kaldet).
    var isAppGone: Bool { number == -600 || number == -609 }
    /// -1712: timeout.
    var isTimeout: Bool { number == -1712 }

    var description: String { "AppleScript-fejl \(number): \(message)" }
}

/// Et kørt script: resultat plus hvornår det startede og sluttede (til `positionTimestamp`).
struct ScriptOutcome: Sendable {
    var result: Result<ScriptValue, ScriptError>
    var started: Date
    var finished: Date

    /// Bedste gæt på hvornår appen læste værdierne: midt i rundturen.
    var measuredAt: Date { started.addingTimeInterval(finished.timeIntervalSince(started) / 2) }
    var milliseconds: Int { Int((finished.timeIntervalSince(started) * 1000).rounded()) }
}

/// Kører AppleScript væk fra main thread.
///
/// NSAppleScript er ikke trådsikker, så ALLE scripts kører på én seriel kø, og de kompilerede
/// scripts (`compiled`) røres kun fra den kø. Scripts kompileres først, når de skal køres
/// (dvs. når appen kører), så vi aldrig slår en app op, der ikke er installeret.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "dk.holgerskov.Pladespiller.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]   // kun på `queue`

    func run(_ source: String) async -> ScriptOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<ScriptOutcome, Never>) in
            queue.async {
                cont.resume(returning: self.runOnQueue(source))
            }
        }
    }

    private func runOnQueue(_ source: String) -> ScriptOutcome {
        let started = Date()
        func done(_ r: Result<ScriptValue, ScriptError>) -> ScriptOutcome {
            ScriptOutcome(result: r, started: started, finished: Date())
        }
        let script: NSAppleScript
        if let s = compiled[source] {
            script = s
        } else {
            guard let s = NSAppleScript(source: source) else {
                return done(.failure(ScriptError(number: -1, message: "Kunne ikke oprette script")))
            }
            var err: NSDictionary?
            if !s.compileAndReturnError(&err) {
                return done(.failure(Self.error(from: err)))
            }
            compiled[source] = s
            script = s
        }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if let err { return done(.failure(Self.error(from: err))) }
        return done(.success(Self.value(from: desc)))
    }

    private static func error(from dict: NSDictionary?) -> ScriptError {
        let n = (dict?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
        let m = dict?[NSAppleScript.errorMessage] as? String ?? "ukendt fejl"
        return ScriptError(number: n, message: m)
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
            return d.typeCodeValue == fcc("msng") ? .missing : .text(d.stringValue ?? fourCCString(d.typeCodeValue))
        case fcc("enum"):
            return .text(d.stringValue ?? fourCCString(d.enumCodeValue))
        default:
            // Fx cover-data ('tdta', 'JPEG', 'PNGf', 'PICT').
            return .data(d.data)
        }
    }

    static func fcc(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func fourCCString(_ c: FourCharCode) -> String {
        String(bytes: [UInt8(c >> 24 & 0xFF), UInt8(c >> 16 & 0xFF), UInt8(c >> 8 & 0xFF), UInt8(c & 0xFF)], encoding: .macOSRoman) ?? "????"
    }
}

/// Bygger scripts der aldrig starter appen: alt pakkes ind i `if application id … is running`.
/// (Swift tjekker også med NSRunningApplication før hvert kald; AppleScript-tjekket lukker
/// kapløbet hvor appen lukker lige før kaldet.)
nonisolated enum AppleScriptTemplate {
    static func guarded(bundleID: String, timeout: Int = 3, body: String, otherwise: String = "return {\"notrunning\"}") -> String {
        """
        if application id "\(bundleID)" is running then
        \ttell application id "\(bundleID)"
        \t\twith timeout of \(timeout) seconds
        \(body.split(separator: "\n", omittingEmptySubsequences: false).map { "\t\t\t" + $0 }.joined(separator: "\n"))
        \t\tend timeout
        \tend tell
        end if
        \(otherwise)
        """
    }
}
