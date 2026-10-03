import Foundation

/// Resultatet af et AppleScript, oversat til en `Sendable` værdi, så det kan sendes fra
/// AppleScript-køen tilbage til main actor (og så parsning kan testes med eksempeldata).
nonisolated enum ScriptValue: Sendable, Equatable {
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

/// Fejl fra et Apple Event eller NSAppleScript.
nonisolated struct ScriptError: Error, Sendable, CustomStringConvertible {
    var number: Int
    var message: String

    /// -1743: brugeren har ikke givet lov (Automatisering).
    var isNotAuthorized: Bool { number == -1743 }
    /// -600/-609: appen kører ikke / forbindelsen er væk (fx lukket lige før kaldet).
    var isAppGone: Bool { number == -600 || number == -609 }
    /// -1744: macOS har ikke spurgt brugeren endnu.
    var needsConsent: Bool { number == -1744 }
    /// -1712: timeout.
    var isTimeout: Bool { number == -1712 }

    var description: String { "AppleScript-fejl \(number): \(message)" }
}

/// Reserve: kører AppleScript-tekst (bruges kun med `--applescript` / `PLADESPILLER_APPLESCRIPT=1`,
/// hvis pid-adresserede Apple Events skulle drille). Samme serielle kø som `AppleEventQueue`, så
/// NSAppleScript aldrig bruges fra to tråde. Scripts kompileres først, når appen kører.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private var compiled: [String: NSAppleScript] = [:]   // kun på køen

    func run(_ source: String) async -> Timed<ScriptValue> {
        await withCheckedContinuation { (cont: CheckedContinuation<Timed<ScriptValue>, Never>) in
            AppleEventQueue.shared.queue.async {
                let started = Date()
                let r = self.runOnQueue(source)
                cont.resume(returning: Timed(result: r, started: started, finished: Date()))
            }
        }
    }

    private func runOnQueue(_ source: String) -> Result<ScriptValue, ScriptError> {
        let script: NSAppleScript
        if let s = compiled[source] {
            script = s
        } else {
            guard let s = NSAppleScript(source: source) else {
                return .failure(ScriptError(number: -1, message: "Kunne ikke oprette script"))
            }
            var err: NSDictionary?
            if !s.compileAndReturnError(&err) { return .failure(Self.error(from: err)) }
            compiled[source] = s
            script = s
        }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if let err { return .failure(Self.error(from: err)) }
        return .success(AE.value(from: desc))
    }

    private static func error(from dict: NSDictionary?) -> ScriptError {
        let n = (dict?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
        let m = dict?[NSAppleScript.errorMessage] as? String ?? "ukendt fejl"
        return ScriptError(number: n, message: m)
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
