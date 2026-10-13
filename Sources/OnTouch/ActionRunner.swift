import AppKit
import CoreGraphics

/// Posts the keystroke for an action. Which binding applies (and whether the
/// app under the cursor is a target at all) is decided by GestureEngine.
final class ActionRunner {
    func perform(action: String) {
        guard action != Keys.none else { return }
        guard let ks = Keys.parse(action) else {
            NSLog("OnTouch: unknown action '\(action)'")
            return
        }
        post(ks)
    }

    /// Bundle identifier of the app owning the front-most window under the
    /// cursor, or nil if it can't be determined.
    static func appUnderCursor() -> String? {
        let mouse = NSEvent.mouseLocation   // Cocoa coords: origin bottom-left of primary screen
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else { return nil }
        // Convert to Quartz coords (origin top-left) used by CGWindowList.
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        // Windows are ordered front-to-back; the first one containing the point
        // is what's visually under the cursor. Skip the cursor itself: recent
        // macOS lists it as a tiny Window Server window at cursor level, which
        // would otherwise always be "under the cursor" and block every gesture.
        let cursorLevel = Int(CGWindowLevelForKey(.cursorWindow))
        for w in windows {
            if let layer = w[kCGWindowLayer as String] as? Int, layer >= cursorLevel { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: b as CFDictionary),
                  bounds.contains(point) else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return nil
    }

    private func post(_ ks: Keystroke) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: false)
        else { return }
        down.flags = ks.flags
        up.flags = ks.flags
        // Mark these as OnTouch's own so the typing monitor ignores them.
        down.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
