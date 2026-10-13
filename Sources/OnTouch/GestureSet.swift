import Foundation

/// What a gesture physically is, independent of what it does.
struct GestureShape: Hashable {
    var anchor = true
    var fingers: Int
    var type: String        // "tap" | "swipe"
    var direction: String   // left/right/up/down, or "any" for taps

    /// Keeps the shape valid when the motion changes ("any" is tap-only).
    mutating func setType(_ t: String) {
        type = t
        if t == "swipe" && direction == "any" { direction = "down" }
    }
}

extension Mapping {
    var shape: GestureShape { GestureShape(anchor: anchor, fingers: fingers, type: type, direction: direction) }

    init(_ s: GestureShape, action: String, apps: [String]? = nil) {
        self.init(anchor: s.anchor, fingers: s.fingers, type: s.type, direction: s.direction, action: action, apps: apps)
    }
}

/// One row in Settings → Gestures.
struct GestureRow: Identifiable {
    let shape: GestureShape
    let action: String
    /// App view: this app has its own version of a default gesture.
    let isCustom: Bool
    /// App view: a gesture that exists only in this app.
    let isAppOnly: Bool
    var id: GestureShape { shape }
}

/// Reading and editing the gesture set the way the Settings UI presents it:
/// a Default set, plus per-app versions that win over it. Edits return a new
/// mappings array; the caller saves it.
extension Config {
    var defaultMappings: [Mapping] { mappings.filter { $0.apps == nil } }

    /// Every app in the sidebar: enabled ones first, then switched-off ones.
    var listedApps: [String] {
        var out: [String] = []
        for id in targetBundleIDs + disabledBundleIDs where id != "*" && !out.contains(id) { out.append(id) }
        return out
    }

    func rows(for app: String?) -> [GestureRow] {
        var seen = Set<GestureShape>()
        let defaults = defaultMappings.filter { seen.insert($0.shape).inserted }
        guard let app else {
            return defaults.map { GestureRow(shape: $0.shape, action: $0.action, isCustom: false, isAppOnly: false) }
        }
        let own = mappings.filter { $0.apps?.contains(app) == true }
        var rows = defaults.map { d -> GestureRow in
            if let mine = own.first(where: { $0.shape == d.shape }) {
                return GestureRow(shape: d.shape, action: mine.action, isCustom: true, isAppOnly: false)
            }
            return GestureRow(shape: d.shape, action: d.action, isCustom: false, isAppOnly: false)
        }
        for m in own where seen.insert(m.shape).inserted {
            rows.append(GestureRow(shape: m.shape, action: m.action, isCustom: true, isAppOnly: true))
        }
        return rows
    }

    func hasOwnGestures(_ app: String) -> Bool {
        mappings.contains { $0.apps?.contains(app) == true }
    }

    // MARK: Edits

    func settingDefault(_ shape: GestureShape, action: String) -> [Mapping] {
        mappings.map { $0.apps == nil && $0.shape == shape ? Mapping(shape, action: action) : $0 }
    }

    /// Nil if `new` is already a default gesture (two can't share a shape).
    func movingDefault(_ old: GestureShape, to new: GestureShape) -> [Mapping]? {
        if old == new { return mappings }
        if defaultMappings.contains(where: { $0.shape == new }) { return nil }
        return mappings.map { $0.apps == nil && $0.shape == old ? Mapping(new, action: $0.action) : $0 }
    }

    /// Gives `app` its own action for `shape`. Choosing the default's action
    /// again just removes the app's version.
    func settingApp(_ app: String, _ shape: GestureShape, action: String) -> [Mapping] {
        var out = removingApp(app, shape)
        let inherited = defaultMappings.first { $0.shape == shape }?.action
        if action != inherited { out.append(Mapping(shape, action: action, apps: [app])) }
        return out
    }

    /// Changes the shape of a gesture that only exists in `app`.
    func movingAppOnly(_ app: String, _ old: GestureShape, to new: GestureShape) -> [Mapping]? {
        if old == new { return mappings }
        if rows(for: app).contains(where: { $0.shape == new }) { return nil }
        guard let action = mappings.first(where: { $0.apps?.contains(app) == true && $0.shape == old })?.action else { return nil }
        var out = removingApp(app, old)
        out.append(Mapping(new, action: action, apps: [app]))
        return out
    }

    /// Drops `app` from its bindings for `shape`, splitting multi-app bindings.
    func removingApp(_ app: String, _ shape: GestureShape) -> [Mapping] {
        mappings.compactMap { m in
            guard m.shape == shape, var apps = m.apps, apps.contains(app) else { return m }
            apps.removeAll { $0 == app }
            if apps.isEmpty { return nil }
            var copy = m
            copy.apps = apps
            return copy
        }
    }
}
