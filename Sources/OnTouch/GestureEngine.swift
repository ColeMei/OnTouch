import Foundation
import AppKit
import CoreGraphics
import CMultitouch

/// Recognizes anchored gestures from raw multitouch frames and matches them
/// against the configured `mappings`. A gesture = an optional held anchor finger
/// plus one or more "acting" fingers that either tap (quick touch near the
/// anchor) or swipe (travel in a direction).
///
/// Each trackpad has its own recognition state: an idle trackpad keeps
/// streaming empty frames, which with one shared state would read as the other
/// trackpad's fingers lifting. Frames may arrive on several MT threads, so
/// `handleFrame` is serialized with a lock.
final class GestureEngine {
    static let shared = GestureEngine()

    /// Number of fingers currently on the trackpad.
    static var liveFingerCount = 0

    /// Uptime of the last frame in which a real gesture was in progress (an
    /// eligible anchor plus at least one acting finger). ClickSuppressor uses
    /// this — not the raw finger count — so a thumb resting on the edge plus a
    /// normal click is NOT mistaken for a gesture and clicks pass through.
    static private(set) var lastGestureUptime: Double = -1000

    /// True if a gesture was in progress within the last `window` seconds (the
    /// grace window covers tap-to-click events that arrive just after lift).
    static func isGesturing(window: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastGestureUptime < window
    }

    var enabled = true

    /// Snapshot of ConfigStore.current, refreshed every frame so config edits
    /// apply without a restart.
    private var cfg = Config()
    private let actions = ActionRunner()

    private struct Touch {
        let id: Int32
        let startTime: Double
        let startPos: CGPoint
        var curPos: CGPoint
        var maxDisp: CGFloat
        var lastSeen: Double
        var shape = TestMonitor.Shape()   // contact ellipse, for the Test tab only
    }

    /// One run of acting (non-anchor) fingers, from first touch to last lift.
    private struct Episode {
        let start: Double
        var peak: Int            // most acting fingers seen at once
        var maxDisp: CGFloat     // furthest any acting finger has moved
        let centroid: CGPoint    // where the acting fingers first landed
        var fired: Bool          // a swipe already fired this episode
    }

    private struct DeviceState {
        var tracked: [Int32: Touch] = [:]
        var episode: Episode?
        var armed = true
    }
    private var states: [UInt: DeviceState] = [:]
    private let lock = NSLock()

    // The state of the device whose frame is being processed.
    private var tracked: [Int32: Touch] = [:]
    private var episode: Episode?
    private var armed = true     // re-armed once acting fingers clear
    private var cooldownUntil: Double = 0   // shared: one action per cooldown, any trackpad
    private var deviceKey: UInt = 0         // the trackpad whose frame is being processed

    /// Forget all touches, e.g. when the devices are reopened.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        states.removeAll()
        cooldownUntil = 0
        tracked.removeAll()
        episode = nil
        Self.liveFingerCount = 0
    }

    func handleFrame(device: MTDeviceRef?, data: UnsafeMutablePointer<Finger>?, count: Int, deviceTime: Double) {
        lock.lock(); defer { lock.unlock() }
        let key = UInt(bitPattern: device)
        deviceKey = key
        let saved = states[key] ?? DeviceState()
        tracked = saved.tracked; episode = saved.episode; armed = saved.armed
        defer { states[key] = DeviceState(tracked: tracked, episode: episode, armed: armed) }
        // Time everything with the system clock, not the frame's timestamp:
        // each device has its own timebase, and a reconnected Bluetooth trackpad
        // restarts near zero — which left the shared cooldown stuck in the future.
        process(data: data, count: count, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private func process(data: UnsafeMutablePointer<Finger>?, count: Int, timestamp now: Double) {
        guard enabled else { tracked.removeAll(); episode = nil; return }
        guard let data = data else { return }
        cfg = ConfigStore.shared.current

        // 1. Ingest current contacts.
        var currentIDs = Set<Int32>()
        for i in 0..<count {
            let f = data[i]
            guard Double(f.size) > cfg.minTouchSize else { continue }
            let pos = CGPoint(x: CGFloat(f.normalized.position.x),
                              y: CGFloat(f.normalized.position.y))
            currentIDs.insert(f.identifier)
            if var t = tracked[f.identifier] {
                t.curPos = pos
                t.maxDisp = max(t.maxDisp, hypot(pos.x - t.startPos.x, pos.y - t.startPos.y))
                t.lastSeen = now
                t.shape = TestMonitor.Shape(f)
                tracked[f.identifier] = t
            } else {
                tracked[f.identifier] = Touch(id: f.identifier, startTime: now,
                                              startPos: pos, curPos: pos, maxDisp: 0, lastSeen: now,
                                              shape: TestMonitor.Shape(f))
            }
        }
        Self.liveFingerCount = currentIDs.count

        // 2. Collect fingers that just lifted.
        var lifted: [Touch] = []
        for id in tracked.keys where !currentIDs.contains(id) {
            if let t = tracked[id] { lifted.append(t) }
            tracked.removeValue(forKey: id)
        }

        // 3. Re-arm as soon as the acting fingers lift (anchor may stay down),
        //    so gestures can be repeated without lifting the anchor.
        if tracked.count <= 1 { armed = true }

        // Touches that STARTED in any edge strip are "resting" — a parked thumb
        // (measured: left edge at mid-height, or top edge near the keyboard).
        // Resting touches can be neither anchors nor acting fingers; otherwise
        // a thumb + a stationary clicking finger reads as anchor + acting =
        // "gesture", wrongly arming click suppression or switching tabs.
        let isResting: (Touch) -> Bool = {
            $0.startPos.y <= CGFloat(self.cfg.anchorEdgeZone)          // bottom
                || $0.startPos.y >= CGFloat(1 - self.cfg.topEdgeZone)  // top
                || $0.startPos.x <= CGFloat(self.cfg.sideEdgeZone)     // left
                || $0.startPos.x >= CGFloat(1 - self.cfg.sideEdgeZone) // right
        }

        // 4. Identify the anchor: a held, near-stationary, non-resting finger.
        let present = Array(tracked.values)
        let anchor = present
            .filter {
                $0.maxDisp < cfg.anchorMaxMove
                    && (now - $0.startTime) >= cfg.anchorMinHold
                    && !isResting($0)
            }
            .min(by: { $0.maxDisp < $1.maxDisp })

        let acting = present.filter { $0.id != anchor?.id && !isResting($0) }
        let actingLifted = lifted.filter { $0.id != anchor?.id && !isResting($0) }
        let frameMaxDisp = (acting.map { $0.maxDisp } + actingLifted.map { $0.maxDisp }).max() ?? 0

        if TestMonitor.active {
            TestMonitor.setTouches(present.map {
                TestMonitor.Touch(id: $0.id, pos: $0.curPos, shape: $0.shape,
                                  role: $0.id == anchor?.id ? .anchor : isResting($0) ? .resting : .acting)
            }, device: deviceKey, time: now)
        }

        // A gesture is "in progress" only when an eligible anchor is planted and
        // another finger is acting — that's what arms click suppression.
        if anchor != nil && !(acting.isEmpty && actingLifted.isEmpty) {
            Self.lastGestureUptime = ProcessInfo.processInfo.systemUptime
        }

        // 5. Maintain the acting-finger episode.
        if !acting.isEmpty {
            if episode == nil {
                episode = Episode(start: now, peak: acting.count, maxDisp: frameMaxDisp,
                                  centroid: centroid(acting.map { $0.startPos }), fired: false)
            } else {
                episode!.peak = max(episode!.peak, acting.count)
                episode!.maxDisp = max(episode!.maxDisp, frameMaxDisp)
            }
        }

        let baseCanFire = now >= cooldownUntil && armed
            && !TypingMonitor.isTyping(window: cfg.typingGuard)
        // Scrolling only blocks TAP gestures (a quick tap during scroll
        // repositioning gets mistaken for a tab switch). Swipe gestures like
        // close-tab are themselves downward motions and need an anchor, so the
        // scroll guard must NOT block them — otherwise closing tabs fails on
        // long, scrollable pages.
        let canFireSwipe = baseCanFire
        let canFireTap = baseCanFire && !ScrollMonitor.isScrolling(window: cfg.scrollGuard)

        // A swipe is inherently deliberate (the fingers travel), so it only
        // needs a stationary anchor present. A tap additionally requires the
        // anchor to have been held BEFORE the tapping finger began — that's what
        // rejects a two-finger tap / right-click (both fingers land together).
        let anchorPresent = anchor != nil
        let anchorLeads: Bool = {
            guard let a = anchor, let ep = episode else { return false }
            return (ep.start - a.startTime) >= cfg.anchorLead
        }()

        // 6a. Swipe — fires mid-gesture, while the acting fingers are still down.
        if canFireSwipe, var ep = episode, !ep.fired, !acting.isEmpty,
           let dir = swipeDirection(acting) {
            if trigger(anchor: anchorPresent, fingers: acting.count, type: "swipe", direction: dir, now) {
                ep.fired = true
                episode = ep
            }
        }

        // 6b. Tap — fires when the acting fingers have all lifted.
        if acting.isEmpty, let ep = episode {
            let duration = now - ep.start
            let dir = tapDirection(ep.centroid, anchor: anchorLeads ? anchor : nil)
            if canFireTap, !ep.fired, duration <= cfg.tapMaxDuration, ep.maxDisp <= cfg.tapMaxMove {
                if !trigger(anchor: anchorLeads, fingers: ep.peak, type: "tap", direction: dir, now), anchorLeads {
                    missed(ep, dir, dir == "none" ? "Too close to the held finger" : "No gesture set",
                           fix: dir == "none" ? "tapMinSep" : nil)
                }
            } else if anchorLeads, !ep.fired, armed, now >= cooldownUntil {
                // An anchored tap that didn't count — say why, for the Test tab.
                if TypingMonitor.isTyping(window: cfg.typingGuard) {
                    missed(ep, dir, "Paused after typing", fix: "typingGuard")
                } else if ScrollMonitor.isScrolling(window: cfg.scrollGuard) {
                    missed(ep, dir, "Paused after scrolling", fix: "scrollGuard")
                } else if ep.maxDisp > cfg.tapMaxMove, ep.maxDisp < cfg.swipeDist {
                    missed(ep, dir, "Moved too far for a tap", fix: "tapMaxMove")
                } else if ep.maxDisp <= cfg.tapMaxMove, duration > cfg.tapMaxDuration {
                    missed(ep, dir, "Held too long for a tap", fix: "tapMaxDuration")
                }
            }
            episode = nil
        }
    }

    // MARK: - Geometry helpers

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.map { $0.x }.reduce(0, +) / n,
                       y: pts.map { $0.y }.reduce(0, +) / n)
    }

    /// Direction of a tap relative to the anchor. Returns "none" (which matches
    /// no directional binding) if there's no anchor or the tap is too close to
    /// it to read a clear direction.
    private func tapDirection(_ c: CGPoint, anchor: Touch?) -> String {
        guard let a = anchor else { return "none" }
        let dx = c.x - a.curPos.x, dy = c.y - a.curPos.y
        let sep = CGFloat(cfg.tapMinSep)
        // Prefer horizontal (tab switching). A left/right tap often lands higher
        // than the anchor too, so we must NOT let that vertical offset reclassify
        // it as up/down — as long as there's clear horizontal separation, it's
        // a left/right tap regardless of how high it landed.
        if abs(dx) >= sep { return dx < 0 ? "left" : "right" }
        if abs(dy) >= sep { return dy < 0 ? "down" : "up" }
        return "none"
    }

    /// Direction of a swipe, or nil if the fingers haven't all moved far enough
    /// in a consistent direction yet.
    private func swipeDirection(_ fs: [Touch]) -> String? {
        let deltas = fs.map { CGPoint(x: $0.curPos.x - $0.startPos.x,
                                      y: $0.curPos.y - $0.startPos.y) }
        let avg = centroid(deltas)
        let d = CGFloat(cfg.swipeDist)
        if abs(avg.x) >= abs(avg.y) {
            guard deltas.allSatisfy({ abs($0.x) >= d && ($0.x < 0) == (avg.x < 0) }) else { return nil }
            return avg.x < 0 ? "left" : "right"
        } else {
            guard deltas.allSatisfy({ abs($0.y) >= d && ($0.y < 0) == (avg.y < 0) }) else { return nil }
            return avg.y < 0 ? "down" : "up"
        }
    }

    /// Reports a tap that almost counted to the Test tab.
    private func missed(_ ep: Episode, _ dir: String, _ why: String, fix key: String?) {
        guard TestMonitor.active else { return }
        let fix = key.flatMap { k in TestMonitor.loosened(k, in: cfg).map { (key: k, value: $0) } }
        TestMonitor.report(.init(fingers: ep.peak, type: "tap", direction: dir,
                                 outcome: .missed, text: why, fix: fix))
    }

    // MARK: - Matching & firing

    /// Runs the binding for this gesture in the app under the cursor: an
    /// app-specific binding wins over the default one, and nothing runs outside
    /// `targetBundleIDs`. Returns true if the gesture is bound at all, even if
    /// nothing ran here — so a swipe isn't re-evaluated every frame.
    @discardableResult
    private func trigger(anchor: Bool, fingers: Int, type: String, direction: String, _ now: Double) -> Bool {
        let bound = cfg.mappings.filter {
            $0.anchor == anchor && $0.fingers == fingers && $0.type == type &&
            ($0.direction == direction || $0.direction == "any")
        }
        guard !bound.isEmpty else { return false }

        let gesture = "\(fingers)-finger \(type) \(direction)"
        let app = ActionRunner.appUnderCursor()
        let everyApp = cfg.targetBundleIDs.isEmpty || cfg.targetBundleIDs.contains("*")
        guard everyApp || app.map(cfg.targetBundleIDs.contains) == true else {
            Log.write("skipped \(gesture) — \(app ?? "unknown app") isn't a target")
            if let app { DispatchQueue.main.async { AppStatus.shared.recordSkip(app: app) } }
            TestMonitor.report(.init(fingers: fingers, type: type, direction: direction,
                                     outcome: .notTarget, text: "", app: app))
            return true
        }
        let specific = app.flatMap { app in bound.first { $0.apps?.contains(app) == true } }
        guard let m = specific ?? bound.first(where: { $0.apps == nil }) else {
            Log.write("skipped \(gesture) — not bound in \(app ?? "unknown app")")
            TestMonitor.report(.init(fingers: fingers, type: type, direction: direction,
                                     outcome: .missed, text: "Off in this app", app: app))
            return true
        }

        Log.write("\(gesture) → \(m.action) in \(app ?? "unknown app")")
        TestMonitor.report(.init(fingers: fingers, type: type, direction: direction,
                                 outcome: .fired, text: Keys.title(for: m.action), app: app))
        actions.perform(action: m.action)
        cooldownUntil = now + cfg.cooldown
        armed = false
        if m.action != Keys.none {
            let haptics = cfg.haptics
            DispatchQueue.main.async {
                // A light tick under the fingers confirms the gesture without
                // anything on screen (Force Touch trackpads only).
                if haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                AppStatus.shared.recordGesture(action: m.action, app: app)
            }
        }
        return true
    }
}
