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
    @Published private(set) var config = Config()
    /// The user's on/off switch; false while paused too.
    @Published private(set) var gesturesOn = true
    @Published private(set) var pausedUntil: Date?
    /// The app in front when the popover opened (OnTouch's own popover takes
    /// focus, so it's captured just before).
    @Published var frontApp: String?

    /// True when gestures can actually reach apps.
    var isWorking: Bool { accessibility && inputMonitoring && trackpads > 0 }

    private var timer: Timer?
    private var resumeTimer: Timer?

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
            Log.write("Accessibility \(ax ? "granted" : "not granted")")
        }
        if im != inputMonitoring {
            inputMonitoring = im
            Log.write("Input Monitoring \(im ? "granted" : "not granted")")
        }
    }

    func setTrackpads(_ count: Int) {
        if count != trackpads { trackpads = count }
    }

    func configChanged(_ store: ConfigStore) {
        config = store.current
        if store.issues != configIssues { configIssues = store.issues }
    }

    // MARK: On / off / pause

    func setGesturesOn(_ on: Bool) {
        resumeTimer?.invalidate()
        pausedUntil = nil
        gesturesOn = on
        GestureEngine.shared.enabled = on
    }

    func pause(for seconds: TimeInterval) {
        setGesturesOn(false)
        pausedUntil = Date().addingTimeInterval(seconds)
        resumeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.setGesturesOn(true)
        }
    }

    func recordGesture(action: String, app: String?) {
        lastGesture = LastGesture(action: action, app: app, date: Date())
    }

    // MARK: App suggestions

    /// An app gestures were tried in that isn't a target yet.
    struct Suggestion: Equatable {
        let bundleID: String
        let tries: Int
    }

    /// Gestures tried in an app this often before it's suggested.
    static let suggestAfter = 5

    /// Tries per non-target app, kept across launches (they add up over days).
    private var skips: [String: Int] = UserDefaults.standard.dictionary(forKey: "skippedTries") as? [String: Int] ?? [:] {
        didSet { UserDefaults.standard.set(skips, forKey: "skippedTries") }
    }
    private var dismissed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "dismissedSuggestions") ?? []) {
        didSet { UserDefaults.standard.set(Array(dismissed), forKey: "dismissedSuggestions") }
    }

    /// The most-tried app worth suggesting, if any. Read again on every config
    /// change, so an app added in Settings stops being suggested.
    var suggestion: Suggestion? {
        let known = Set(config.targetBundleIDs + config.disabledBundleIDs)
        return skips
            .filter { $0.value >= Self.suggestAfter && !known.contains($0.key) && !dismissed.contains($0.key) }
            .max { $0.value < $1.value }
            .map { Suggestion(bundleID: $0.key, tries: $0.value) }
    }

    func recordSkip(app: String) {
        // Only real apps: menu-bar helpers, Notification Center, and OnTouch's
        // own windows aren't places anyone means to switch tabs.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app)
                .first?.activationPolicy == .regular else { return }
        objectWillChange.send()
        skips[app, default: 0] += 1
    }

    func dismissSuggestion(_ id: String) {
        objectWillChange.send()
        dismissed.insert(id)
    }

    func acceptSuggestion(_ id: String) {
        objectWillChange.send()
        skips[id] = nil
        ConfigEdits.setApp(id, enabled: true)
    }
}
