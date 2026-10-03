import Foundation

/// Lytter på distribuerede notifikationer med `.deliverImmediately`. Den blok-baserede
/// `addObserver(forName:…)` har ingen `suspensionBehavior` og bliver holdt tilbage, mens appen er
/// inaktiv — og det er Pladespiller altid (LSUIElement, non-activating panel).
/// Afmelder sig selv, når den frigives. Fælles for NowPlaying/ og Window/.
final class DistributedObserver: NSObject {
    private let handler: ([AnyHashable: Any]?) -> Void

    init(names: [Notification.Name], handler: @escaping ([AnyHashable: Any]?) -> Void) {
        self.handler = handler
        super.init()
        for name in names {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: name,
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    convenience init(name: Notification.Name, handler: @escaping ([AnyHashable: Any]?) -> Void) {
        self.init(names: [name], handler: handler)
    }

    /// Til observere der kun skal vide, at noget er ændret.
    convenience init(names: [String], onChange: @escaping () -> Void) {
        self.init(names: names.map { Notification.Name($0) }, handler: { _ in onChange() })
    }

    isolated deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc nonisolated private func received(_ note: Notification) {
        nonisolated(unsafe) let info = note.userInfo
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler(info) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.handler(info) } }
        }
    }
}
