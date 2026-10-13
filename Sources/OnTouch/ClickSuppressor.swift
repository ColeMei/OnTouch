import CoreGraphics
import Foundation

/// While a gesture is in progress (2+ fingers on the trackpad), a "tap to
/// click" tap would otherwise register as a left click — clicking links under
/// the cursor instead of just switching tabs. This event tap drops those
/// clicks so gestures don't activate whatever is under the pointer.
private func clickTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                             event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if the system disabled it.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = ClickSuppressor.shared?.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    guard GestureEngine.shared.enabled else { return Unmanaged.passUnretained(event) }

    // Suppress clicks only while an actual gesture is in progress (anchor +
    // acting finger), not merely when 2+ fingers touch the pad — a thumb
    // resting on the edge plus a normal click must still click.
    // And only over apps where gestures act — elsewhere (Settings included) a
    // resting finger plus a click is just a click.
    let suppressor = ClickSuppressor.shared
    if type == .leftMouseDown, GestureEngine.isGesturing(window: 0.25), ClickSuppressor.cursorOverTarget() {
        suppressor?.pendingSuppressUp = true
        return nil                      // drop the click
    }
    // Drop a release only if its press was dropped: a release on its own
    // would leave the app thinking the button is still held (a stuck drag).
    if type == .leftMouseUp, suppressor?.pendingSuppressUp == true {
        suppressor?.pendingSuppressUp = false
        return nil
    }
    return Unmanaged.passUnretained(event)
}

final class ClickSuppressor {
    static var shared: ClickSuppressor?
    var tap: CFMachPort?
    var pendingSuppressUp = false

    /// True if the window under the cursor belongs to an app gestures act in.
    static func cursorOverTarget() -> Bool {
        let targets = ConfigStore.shared.current.targetBundleIDs
        let app = ActionRunner.appUnderCursor()
        if app == Bundle.main.bundleIdentifier { return false }
        if targets.isEmpty || targets.contains("*") { return true }
        return app.map(targets.contains) ?? false
    }

    func start() {
        ClickSuppressor.shared = self
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: clickTapCallback,
                                          userInfo: nil) else {
            Log.write("could not create click event tap (needs Accessibility)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("click suppressor active")
    }
}
