import AppKit

extension NSScreen {
    /// Stabilt skærm-id: skærmens UUID (overlever genstart og ny tilslutning), ellers displaynummeret.
    var stableID: String {
        guard let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "ukendt"
        }
        let displayID = CGDirectDisplayID(n.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let s = CFUUIDCreateString(nil, uuid) as String? {
            return s
        }
        return "display-\(displayID)"
    }
}

/// Apples widget-vinduer lige nu (AppKit-koordinater). Læses kun ved behov (træk, placering) –
/// ingen polling. Kræver ikke skærmoptagelses-tilladelse: vi bruger kun ramme, lag og PID.
enum AppleWidgetWindows {
    nonisolated static let ownerBundleID = "com.apple.notificationcenterui"

    static func frames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let level = WidgetMetrics.windowLevel.rawValue
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ncPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: ownerBundleID)
            .map(\.processIdentifier))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? Int) == level,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  ncPIDs.contains(pid) || (info[kCGWindowOwnerName as String] as? String) == "Notification Center",
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict),
                  r.width >= 100, r.height >= 100 else { return nil }
            return GridSnapper.appKitRect(fromCG: r, primaryScreenHeight: primaryHeight)
        }
    }
}
