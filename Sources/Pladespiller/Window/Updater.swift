import AppKit
import Security

/// "Søg efter opdatering…" i højrekliksmenuen.
///
/// Spørger GitHub efter den nyeste udgivelse af Pladespiller. Er den nyere end den, der kører, kan man hente den:
/// zip-filen fra udgivelsen pakkes ud, det tjekkes at det er Pladespiller i den lovede version og signeret med samme
/// certifikat som appen, der kører, og så skiftes appen ud og startes igen.
///
/// Der sendes kun noget til GitHub, når man selv vælger menupunktet (appen tjekker ikke af sig selv).
enum Updater {
    static let repo = "Agg3mam/pladespiller"
    static let assetName = "Pladespiller.zip"

    struct Release {
        let version: String
        let zip: URL
        let notes: String
    }

    enum Failure: Error {
        case network(String)
        case noDownload
        case badArchive
        case wrongApp
        case badSignature
        case cannotReplace

        @MainActor var text: String {
            switch self {
            case .network(let s): L("Kunne ikke få fat i GitHub (\(s)).", "Could not reach GitHub (\(s)).")
            case .noDownload: L("Den nyeste udgivelse har ingen Pladespiller.zip.", "The latest release has no Pladespiller.zip.")
            case .badArchive: L("Den hentede fil kunne ikke pakkes ud.", "The downloaded file could not be unpacked.")
            case .wrongApp: L("Den hentede fil er ikke den forventede version af Pladespiller.", "The download is not the expected version of Pladespiller.")
            case .badSignature: L("Den hentede app er ikke signeret som den, du har. Den er ikke installeret.",
                                  "The downloaded app is not signed like the one you have. It was not installed.")
            case .cannotReplace: L("Appen kan ikke skiftes ud, hvor den ligger nu.", "The app cannot be replaced where it is now.")
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "0.10" er nyere end "0.9": tallene sammenlignes ét ad gangen.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: GitHub

    static func latest() async throws(Failure) -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pladespiller", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw .network(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw .network("HTTP \(status)") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw .network(L("uventet svar", "unexpected answer")) }
        let assets = json["assets"] as? [[String: Any]] ?? []
        // Kun selve zip-filen fra udgivelsen på github.com, over https.
        guard let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link),
              url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/\(repo)/releases/download/") else { throw .noDownload }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, zip: url, notes: (json["body"] as? String) ?? "")
    }

    /// Henter og pakker udgivelsen ud i en midlertidig mappe og tjekker den. Returnerer den nye app.
    static func download(_ release: Release) async throws(Failure) -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Pladespiller-opdatering-\(UUID().uuidString)", isDirectory: true)
        let zip = dir.appendingPathComponent(assetName), unpacked = dir.appendingPathComponent("ud", isDirectory: true)
        do {
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let (file, response) = try await URLSession.shared.download(from: release.zip)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.network("HTTP") }
            try fm.moveItem(at: file, to: zip)
        } catch let f as Failure {
            throw f
        } catch {
            throw .network(error.localizedDescription)
        }
        let ok = await Task.detached { () -> Bool in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, unpacked.path]
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
        let app = unpacked.appendingPathComponent("Pladespiller.app", isDirectory: true)
        guard ok, fm.fileExists(atPath: app.path) else { throw .badArchive }
        try verify(app, version: release.version)
        return app
    }

    /// Er det Pladespiller i den lovede version – og signeret med samme certifikat som appen, der kører?
    static func verify(_ app: URL, version: String) throws(Failure) {
        let expectedID = Bundle.main.bundleIdentifier ?? "dk.holgerskov.Pladespiller"
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == expectedID,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version else { throw .wrongApp }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw .badSignature }
        // Kravet: samme underskriver som os selv. (En testbygning uden rigtig signatur kan kun tjekke, at den nye er hel.)
        var requirement: SecRequirement?
        var me: SecCode?
        if SecCodeCopySelf([], &me) == errSecSuccess, let me {
            var mine: SecStaticCode?
            var info: CFDictionary?
            if SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
               SecCodeCopySigningInformation(mine, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
               let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32,
               flags & SecCodeSignatureFlags.adhoc.rawValue == 0 {
                SecCodeCopyDesignatedRequirement(mine, [], &requirement)
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw .badSignature }
    }

    /// Skift appen ud og start den nye: et lille script venter på, at vi er lukket, bytter mapperne og åbner appen.
    /// Går byttet galt, lægges den gamle app tilbage.
    static func install(_ newApp: URL) throws(Failure) {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw .cannotReplace }
        let script = """
        pid="$1"; new="$2"; target="$3"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$target.gammel"
        if mv "$target" "$target.gammel" && mv "$new" "$target"; then rm -rf "$target.gammel"; else mv "$target.gammel" "$target" 2>/dev/null; fi
        open "$target"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), newApp.path, target.path]
        do { try p.run() } catch { throw .cannotReplace }
        NSApp.terminate(nil)
    }

    // MARK: Menupunktet

    private static var busy = false

    /// Hele forløbet fra menuen, med dialoger.
    static func checkFromMenu() {
        guard !busy else { return }
        busy = true
        let previous = NSWorkspace.shared.frontmostApplication
        func giveBack() { if let previous, previous != NSRunningApplication.current { previous.activate() } }
        Task {
            defer { busy = false }
            do {
                let release = try await latest()
                guard isNewer(release.version, than: currentVersion) else {
                    show(L("Du har den nyeste version", "You have the latest version"),
                         L("Pladespiller \(currentVersion) er den nyeste.", "Pladespiller \(currentVersion) is the latest."))
                    giveBack()
                    return
                }
                var notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if notes.count > 600 { notes = String(notes.prefix(600)) + "…" }
                let go = ask(L("Pladespiller \(release.version) er klar", "Pladespiller \(release.version) is available"),
                             L("Du har version \(currentVersion). Appen hentes fra GitHub, skiftes ud og starter igen.",
                               "You have version \(currentVersion). The app is downloaded from GitHub, replaced and restarted.")
                                 + (notes.isEmpty ? "" : "\n\n" + notes),
                             yes: L("Opdatér", "Update"), no: L("Senere", "Later"))
                guard go else { giveBack(); return }
                let app = try await download(release)
                try install(app)
            } catch let failure as Failure {
                show(L("Opdateringen lykkedes ikke", "The update did not succeed"), failure.text)
                giveBack()
            } catch {
                show(L("Opdateringen lykkedes ikke", "The update did not succeed"), error.localizedDescription)
                giveBack()
            }
        }
    }

    private static func alert(_ title: String, _ text: String) -> NSAlert {
        // En accessory-app skal aktiveres, for at dialogen kan få fokus.
        NSApp.activate()
        let a = NSAlert()
        a.alertStyle = .informational
        a.messageText = title
        a.informativeText = text
        a.window.level = .modalPanel
        return a
    }

    private static func show(_ title: String, _ text: String) {
        let a = alert(title, text)
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private static func ask(_ title: String, _ text: String, yes: String, no: String) -> Bool {
        let a = alert(title, text)
        a.addButton(withTitle: yes)
        a.addButton(withTitle: no).keyEquivalent = "\u{1b}"
        return a.runModal() == .alertFirstButtonReturn
    }

    // MARK: Test fra Terminal

    /// `--update-check [--download] [--as <version>]`: skriv hvad GitHub svarer, og hent/tjek evt. filen uden at installere.
    static func debugCheck(download wantsDownload: Bool, pretend: String?) async -> Int32 {
        let mine = pretend ?? currentVersion
        do {
            let release = try await latest()
            print("Denne version: \(mine)")
            print("Nyeste på GitHub: \(release.version)  (\(release.zip.absoluteString))")
            print(isNewer(release.version, than: mine) ? "→ Der er en opdatering." : "→ Du har den nyeste.")
            guard wantsDownload else { return 0 }
            let app = try await self.download(release)
            print("Hentet, pakket ud og godkendt: \(app.path)")
            try? FileManager.default.removeItem(at: app.deletingLastPathComponent().deletingLastPathComponent())
            return 0
        } catch let failure as Failure {
            print("FEJL: \(failure.text)")
            return 1
        } catch {
            print("FEJL: \(error.localizedDescription)")
            return 1
        }
    }
}
