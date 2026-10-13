import Foundation

/// OnTouch's activity log: every line goes to the system log (NSLog) and to
/// ~/Library/Logs/OnTouch.log, which Settings → Log opens. Safe from any thread.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/OnTouch.log")

    /// Past this size the log moves to OnTouch.log.1 and starts over.
    private static let maxBytes = 1_000_000
    private static let queue = DispatchQueue(label: "OnTouch.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        NSLog("OnTouch: %@", message)
        let now = Date()
        queue.async {
            let line = "\(stamp.string(from: now))  \(message)\n"
            append(Data(line.utf8))
        }
    }

    private static func append(_ data: Data) {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)     // the previous rotation, not user data
            try? fm.moveItem(at: url, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
