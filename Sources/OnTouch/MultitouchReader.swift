import AppKit
import CMultitouch
import IOKit
import IOKit.hid

/// Global C callback — a non-capturing function so it can be passed where a
/// C function pointer is expected. It simply forwards every frame to the engine.
private func mtFrameCallback(_ device: MTDeviceRef?,
                            _ touches: UnsafeMutablePointer<Finger>?,
                            _ numTouches: Int32,
                            _ timestamp: Double,
                            _ frame: Int32) -> Int32 {
    GestureEngine.shared.handleFrame(data: touches,
                                     count: Int(numTouches),
                                     timestamp: timestamp)
    return 0
}

/// IOKit callback for multitouch devices appearing or disappearing.
private func deviceChangedCallback(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    MultitouchReader.drain(iterator)
    guard let refcon else { return }
    Unmanaged<MultitouchReader>.fromOpaque(refcon).takeUnretainedValue().scheduleRestart()
}

/// Opens every multitouch device and streams frames to the gesture engine.
/// Reopens them when a trackpad connects or disconnects (e.g. a Bluetooth
/// Magic Trackpad) and after the Mac wakes, since the device handles opened at
/// launch can go stale either way. Main thread only.
final class MultitouchReader {
    private var devices: [MTDeviceRef] = []
    /// Owns the device refs in `devices`; released only when we restart.
    private var deviceList: CFMutableArray?
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pendingRestart: DispatchWorkItem?

    /// Called after (re)starting, with the number of devices now streaming.
    var onChange: ((Int) -> Void)?

    var deviceCount: Int { devices.count }

    /// True if at least one multitouch device started streaming.
    @discardableResult
    func start() -> Bool {
        // Ask for Input Monitoring up front (required on recent macOS to read
        // raw HID/multitouch data).
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openDevices()
        watchDevices()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRestart(after: 2) }
        return !devices.isEmpty
    }

    func stop() {
        for device in devices {
            if MTDeviceIsRunning(device) { MTDeviceStop(device) }
            MTUnregisterContactFrameCallback(device, mtFrameCallback)
        }
        devices.removeAll()
        deviceList = nil
    }

    /// Reopen all devices once things settle — a device that just appeared
    /// isn't always ready to stream immediately.
    func scheduleRestart(after delay: Double = 1) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restart() }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restart() {
        stop()
        // Fingers that were down when we stopped must not read as lifts (taps).
        GestureEngine.shared.reset()
        openDevices()
    }

    private func openDevices() {
        guard let list = MTDeviceCreateList()?.takeRetainedValue() else {
            NSLog("OnTouch: MTDeviceCreateList returned nil")
            onChange?(0)
            return
        }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = MTDeviceRef(mutating: raw)
            MTRegisterContactFrameCallback(device, mtFrameCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
        }
        NSLog("OnTouch: started \(devices.count) multitouch device(s)")
        onChange?(devices.count)
    }

    private func watchDevices() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let kr = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"),
                                                      deviceChangedCallback, refcon, &iterator)
            guard kr == KERN_SUCCESS else {
                NSLog("OnTouch: can't watch for trackpad changes (\(kr))")
                continue
            }
            // Drain once to arm the notification; existing devices are already open.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}
