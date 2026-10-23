import Foundation
import CoreGraphics
import CMultitouch

/// What Settings → Test shows: the fingers OnTouch sees right now and what it
/// made of the last few gestures — including near misses and why, so a
/// threshold can be loosened without reading the log.
///
/// GestureEngine feeds it from the multitouch thread only while `active`.
final class TestMonitor: ObservableObject {
    static let shared = TestMonitor()

    /// Set by the Test tab while it's on screen.
    static var active = false

    /// A finger's contact ellipse as the trackpad reports it.
    struct Shape {
        var major: CGFloat = 0      // axes, roughly mm
        var minor: CGFloat = 0
        var angle: CGFloat = 0      // radians

        init() {}
        init(_ f: Finger) {
            major = CGFloat(f.majorAxis); minor = CGFloat(f.minorAxis); angle = CGFloat(f.angle)
        }
    }

    struct Touch {
        enum Role { case anchor, acting, resting }
        let id: Int32
        let pos: CGPoint        // normalized, origin bottom-left
        let shape: Shape
        let role: Role
    }

    /// The trackpad last touched: its fingers and its surface in mm.
    struct Pad {
        var touches: [Touch] = []
        var size = CGSize(width: 160, height: 115)   // Magic Trackpad, until measured
    }

    struct Event: Identifiable {
        enum Outcome { case fired, missed, notTarget }
        let id = UUID()
        let fingers: Int
        let type: String
        let direction: String
        let outcome: Outcome
        let text: String
        var app: String? = nil
        /// A config change that would have let this gesture through.
        var fix: (key: String, value: Double)? = nil
    }

    @Published private(set) var events: [Event] = []

    private static let lock = NSLock()
    private static var pads: [UInt: Pad] = [:]
    private static var lastDevice: UInt = 0
    private static var lastTouched: Double = 0

    /// The trackpad in use: the one with fingers on it, else the last one that had.
    static var pad: Pad {
        lock.lock(); defer { lock.unlock() }
        return pads[lastDevice] ?? Pad()
    }

    static func setTouches(_ t: [Touch], device: UInt, time: Double) {
        guard active else { return }
        lock.lock(); defer { lock.unlock() }
        if pads[device] == nil { pads[device] = Pad(size: surface(device)) }
        pads[device]!.touches = t
        // An idle trackpad keeps sending empty frames; don't let it take over
        // the drawing from the one being used.
        if !t.isEmpty || device == lastDevice || time - lastTouched > 1 {
            if !t.isEmpty { lastTouched = time }
            lastDevice = device
        }
    }

    private static func surface(_ device: UInt) -> CGSize {
        var w: Int32 = 0, h: Int32 = 0
        guard let ref = UnsafeMutableRawPointer(bitPattern: device),
              MTDeviceGetSensorSurfaceDimensions(ref, &w, &h) == 0, w > 0, h > 0
        else { return Pad().size }
        Log.write("trackpad surface \(w / 100)×\(h / 100) mm")
        return CGSize(width: CGFloat(w) / 100, height: CGFloat(h) / 100)
    }

    static func report(_ e: Event) {
        guard active else { return }
        DispatchQueue.main.async {
            shared.events.insert(e, at: 0)
            if shared.events.count > 4 { shared.events.removeLast() }
        }
    }

    /// The next, looser value for a threshold, or nil once it's as loose as it
    /// sensibly gets.
    static func loosened(_ key: String, in cfg: Config) -> Double? {
        let (cur, step, limit): (Double, Double, Double)
        switch key {
        case "tapMaxMove":     (cur, step, limit) = (cfg.tapMaxMove, 0.02, 0.16)
        case "tapMaxDuration": (cur, step, limit) = (cfg.tapMaxDuration, 0.05, 0.6)
        case "tapMinSep":      (cur, step, limit) = (cfg.tapMinSep, -0.01, 0.03)
        case "typingGuard":    (cur, step, limit) = (cfg.typingGuard, -0.1, 0)
        case "scrollGuard":    (cur, step, limit) = (cfg.scrollGuard, -0.1, 0)
        default: return nil
        }
        let next = ((cur + step) * 100).rounded() / 100
        return step > 0 ? (cur < limit ? min(next, limit) : nil) : (cur > limit ? max(next, limit) : nil)
    }
}
