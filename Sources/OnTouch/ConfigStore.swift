import Foundation

/// Owns the config file: loads it, reloads it whenever it changes on disk, and
/// keeps the last *valid* config in force when the file has problems — those
/// are reported in `issues` instead of silently falling back to defaults.
///
/// `current` is read from the multitouch thread every frame and replaced on the
/// main thread, so it sits behind a lock. Everything else is main-thread only.
final class ConfigStore {
    static let shared = ConfigStore()

    static let directory = ("~/.config/ontouch" as NSString).expandingTildeInPath
    static let path = directory + "/config.json"
    /// Upstream's location; copied to `path` on first launch.
    static let legacyPath = ("~/.config/trackpad-tabs/config.json" as NSString).expandingTildeInPath

    private let lock = NSLock()
    private var _current = Config()

    /// The config gestures run with right now.
    var current: Config {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    /// Human-readable problems with the file on disk; empty when it's fine.
    private(set) var issues: [String] = []

    /// Called on the main thread after every reload attempt.
    var onChange: (() -> Void)?

    private var watcher: DispatchSourceFileSystemObject?
    private var lastData: Data?
    private var pendingReload: DispatchWorkItem?

    func start() {
        migrateLegacyFile()
        reload()
        watch()
    }

    // MARK: Loading

    func reload() {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: Self.path) else {
            lastData = nil
            apply(Config(), issues: [])
            return
        }
        guard data != lastData else { return }
        lastData = data

        let cfg: Config
        do {
            cfg = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            report([Self.describe(error)])
            return
        }
        let problems = cfg.validate(text: String(decoding: data, as: UTF8.self))
        if !problems.isEmpty {
            report(problems)
            return
        }
        NSLog("OnTouch: config loaded from \(Self.path) (\(cfg.mappings.count) gestures)")
        apply(cfg, issues: [])
    }

    private func apply(_ cfg: Config, issues: [String]) {
        lock.lock(); _current = cfg; lock.unlock()
        self.issues = issues
        onChange?()
    }

    /// Keep the last good config; just surface what's wrong.
    private func report(_ problems: [String]) {
        for p in problems { NSLog("OnTouch: config problem — \(p)") }
        issues = problems
        onChange?()
    }

    private func migrateLegacyFile() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.directory, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: Self.path), fm.fileExists(atPath: Self.legacyPath) else { return }
        do {
            try fm.copyItem(atPath: Self.legacyPath, toPath: Self.path)
            NSLog("OnTouch: copied config from \(Self.legacyPath) to \(Self.path)")
        } catch {
            NSLog("OnTouch: could not copy legacy config: \(error)")
        }
    }

    // MARK: Watching

    /// Watch the directory, not the file: editors usually save by writing a new
    /// file and renaming it over the old one, which a file watch would miss.
    private func watch() {
        let fd = open(Self.directory, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("OnTouch: can't watch \(Self.directory) for config changes")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Editors can touch the directory several times per save; settle first.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: Error text

    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        switch e {
        case .dataCorrupted(let ctx):
            // JSONSerialization's message already names the line and column.
            if let ns = ctx.underlyingError as NSError?,
               let msg = ns.userInfo["NSDebugDescription"] as? String {
                return "Not valid JSON: \(msg)"
            }
            return "Not valid JSON: \(ctx.debugDescription)"
        case .typeMismatch(let type, let ctx), .valueNotFound(let type, let ctx):
            return "\(codingPath(ctx.codingPath)): expected \(typeName(type))"
        case .keyNotFound(let key, let ctx):
            return "\(codingPath(ctx.codingPath + [key])): missing"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }
            .joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: return "text"
        case is Bool.Type: return "true or false"
        case is Int.Type, is Double.Type: return "a number"
        case is [String].Type: return "a list of text"
        default: return "\(type)"
        }
    }
}

// MARK: - Validation

extension Config {
    /// Problems that decode fine but can't work, e.g. a misspelled action.
    /// `text` is the raw file, used to point at line numbers.
    func validate(text: String) -> [String] {
        var problems: [String] = []
        let lines = text.components(separatedBy: "\n")
        func at(_ needle: String) -> String {
            guard let i = lines.firstIndex(where: { $0.contains("\"\(needle)\"") }) else { return "" }
            return "Line \(i + 1): "
        }

        for m in mappings {
            if m.type != "tap" && m.type != "swipe" {
                problems.append(at(m.type) + "unknown gesture type “\(m.type)” (use tap or swipe)")
            }
            let dirs = m.type == "tap" ? ["left", "right", "up", "down", "any"] : ["left", "right", "up", "down"]
            if !dirs.contains(m.direction) {
                problems.append(at(m.direction) + "“\(m.direction)” isn’t a direction for a \(m.type)")
            }
            if !(1...5).contains(m.fingers) {
                problems.append("A gesture uses \(m.fingers) fingers (use 1 to 5)")
            }
            if m.action != Keys.none && Keys.parse(m.action) == nil {
                var msg = at(m.action) + "unknown action “\(m.action)”"
                if let s = Keys.suggestion(for: m.action) { msg += " — did you mean “\(s)”?" }
                problems.append(msg)
            }
        }
        return problems
    }
}
