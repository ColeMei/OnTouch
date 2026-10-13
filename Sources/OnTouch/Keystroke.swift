import CoreGraphics

/// A resolved key event: a virtual key code plus modifier flags.
struct Keystroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Resolves action strings into keystrokes. An action is either a built-in
/// name (e.g. "nextTab") or a literal chord (e.g. "cmd+shift+t").
enum Keys {
    /// Friendly action names → key chords. Browser-focused, but any chord works.
    static let builtins: [String: String] = [
        "nextTab":       "ctrl+tab",
        "prevTab":       "ctrl+shift+tab",
        "closeTab":      "cmd+w",
        "newTab":        "cmd+t",
        "reopenTab":     "cmd+shift+t",
        "closeWindow":   "cmd+shift+w",
        "reload":        "cmd+r",
        "back":          "cmd+[",
        "forward":       "cmd+]",
        "newWindow":     "cmd+n",
        "privateWindow": "cmd+shift+n",
        "showAllTabs":   "cmd+shift+backslash",
        "zoomIn":        "cmd+=",
        "zoomOut":       "cmd+-",
        "firstTab":      "cmd+1",
    ]

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
    ]

    /// Named keys and symbols → virtual key codes (kVK_*).
    private static let namedKeys: [String: CGKeyCode] = [
        "tab": 48, "space": 49, "return": 36, "enter": 36, "delete": 51,
        "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "[": 33, "]": 30, "backslash": 42, "\\": 42,
        "=": 24, "-": 27, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    private static let letters: [Character: CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,
        "l":37,"j":38,"k":40,"n":45,"m":46,
        "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,
    ]

    /// What the UI calls each built-in action.
    static let titles: [String: String] = [
        "nextTab": "Next tab", "prevTab": "Previous tab", "closeTab": "Close tab",
        "newTab": "New tab", "reopenTab": "Reopen tab", "closeWindow": "Close window",
        "reload": "Reload", "back": "Back", "forward": "Forward",
        "newWindow": "New window", "privateWindow": "Private window",
        "showAllTabs": "Show all tabs", "zoomIn": "Zoom in", "zoomOut": "Zoom out",
        "firstTab": "First tab",
    ]

    /// "Next tab" for a built-in, "⌘L" for a custom chord, "Off" for none.
    static func title(for action: String) -> String {
        if action == none { return "Off" }
        return titles[action] ?? symbols(for: action)
    }

    /// The chord as macOS shows shortcuts, e.g. "⌃⇧⇥" or "⇧⌘T".
    static func symbols(for action: String) -> String {
        if action == none { return "" }
        let parts = (builtins[action] ?? action).lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last else { return action }
        let mods = Set(parts.dropLast())
        var out = ""
        if mods.contains("ctrl") || mods.contains("control") { out += "⌃" }
        if mods.contains("alt") || mods.contains("opt") || mods.contains("option") { out += "⌥" }
        if mods.contains("shift") { out += "⇧" }
        if mods.contains("cmd") || mods.contains("command") { out += "⌘" }
        let keySymbols = ["tab": "⇥", "space": "Space", "return": "↩", "enter": "↩", "delete": "⌫",
                          "escape": "⎋", "esc": "⎋", "left": "←", "right": "→", "up": "↑", "down": "↓",
                          "backslash": "\\"]
        return out + (keySymbols[key] ?? key.uppercased())
    }

    /// The action that switches a gesture off (e.g. in one app).
    static let none = "none"

    /// The built-in name closest to a misspelled action, if any is close.
    static func suggestion(for action: String) -> String? {
        let a = action.lowercased()
        let scored = builtins.keys.map { ($0, editDistance(a, $0.lowercased())) }
        guard let best = scored.min(by: { $0.1 < $1.1 }), best.1 <= 2 else { return nil }
        return best.0
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var diag = row[0]
            row[0] = i
            for j in 1...b.count {
                let up = row[j]
                row[j] = min(up + 1, row[j - 1] + 1, diag + (a[i - 1] == b[j - 1] ? 0 : 1))
                diag = up
            }
        }
        return row[b.count]
    }

    /// Parse "cmd+shift+t" (or a built-in name) into a Keystroke.
    static func parse(_ action: String) -> Keystroke? {
        let chord = builtins[action] ?? action
        let parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = parts.last else { return nil }

        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            guard let f = modifiers[mod] else { return nil }
            flags.insert(f)
        }

        let keyCode: CGKeyCode
        if let k = namedKeys[keyToken] {
            keyCode = k
        } else if keyToken.count == 1, let k = letters[keyToken.first!] {
            keyCode = k
        } else {
            return nil
        }
        return Keystroke(keyCode: keyCode, flags: flags)
    }
}
