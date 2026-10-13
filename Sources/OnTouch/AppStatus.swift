import AppKit
import ApplicationServices
import Combine
import IOKit.hid

/// Everything the UI shows about whether OnTouch is working. Main thread only.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    struct LastGesture: Equatable {
        let action: String
        let app: String?
        let date: Date
    }

    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var trackpads = 0
    @Published private(set) var lastGesture: LastGesture?
    @Published private(set) var configIssues: [String] = []

    /// True when gestures can actually reach apps.
    var isWorking: Bool { accessibility && inputMonitoring && trackpads > 0 }

    private var timer: Timer?

    /// Permissions have no change notifications, so poll — cheaply, and only
    /// publish when something actually changed.
    func start() {
        refreshPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func refreshPermissions() {
        let ax = AXIsProcessTrusted()
        let im = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if ax != accessibility {
            accessibility = ax
            NSLog("OnTouch: Accessibility \(ax ? "granted" : "not granted")")
        }
        if im != inputMonitoring {
            inputMonitoring = im
            NSLog("OnTouch: Input Monitoring \(im ? "granted" : "not granted")")
        }
    }

    func setTrackpads(_ count: Int) {
        if count != trackpads { trackpads = count }
    }

    func setConfigIssues(_ issues: [String]) {
        if issues != configIssues { configIssues = issues }
    }

    func recordGesture(action: String, app: String?) {
        lastGesture = LastGesture(action: action, app: app, date: Date())
    }
}
