import AppKit
import CoreGraphics

struct WindowInfo: Equatable {
    let ownerName: String
    let title: String
}

/// Detects whether the user is in a Zoom *call* (not just running Zoom).
enum ZoomDetector {

    static func isInMeeting(windows: [WindowInfo]) -> Bool {
        windows.contains { w in
            w.ownerName.lowercased().contains("zoom")
                && w.title.lowercased().contains("meeting")
        }
    }

    /// On-screen windows via CGWindowList. Titles need Screen Recording
    /// permission (already held for system audio); without it, titles are empty
    /// and `isInMeeting` degrades to `false` — callers fall back to `zoomRunning`.
    static func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.map { dict in
            WindowInfo(
                ownerName: dict[kCGWindowOwnerName as String] as? String ?? "",
                title: dict[kCGWindowName as String] as? String ?? ""
            )
        }
    }

    static func zoomRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "us.zoom.xos" }
    }

    /// Live decision: prefer the precise window-title check; if titles are
    /// unavailable (no Screen Recording permission) fall back to "Zoom is
    /// running with an on-screen window".
    static func liveIsInMeeting() -> Bool {
        let windows = currentWindows()
        if isInMeeting(windows: windows) { return true }
        let titlesReadable = windows.contains { !$0.title.isEmpty }
        if titlesReadable { return false }
        return zoomRunning() && windows.contains { $0.ownerName.lowercased().contains("zoom") }
    }
}
