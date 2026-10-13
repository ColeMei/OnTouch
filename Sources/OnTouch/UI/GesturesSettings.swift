import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Gestures: a sidebar with the Default set and each app, and the
/// selected set's gestures. Clicking a gesture expands an inline editor.
struct GesturesSettings: View {
    @ObservedObject var status: AppStatus
    @StateObject private var model = GesturesModel()

    private var cfg: Config { status.config }
    /// nil = the Default set.
    private var app: String? { model.selection == GesturesModel.defaultID ? nil : model.selection }
    private var appOn: Bool { app.map { cfg.targetBundleIDs.contains($0) } ?? true }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            detail
        }
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding<String?>(get: { model.selection },
                                             set: { model.select($0 ?? GesturesModel.defaultID) })) {
                sidebarRow(nil).tag(GesturesModel.defaultID)
                Section("Apps") {
                    ForEach(cfg.listedApps, id: \.self) { id in sidebarRow(id).tag(id) }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 2) {
                Button { addApp() } label: { Image(systemName: "plus").frame(width: 22, height: 22) }
                    .accessibilityLabel("Add app")
                Button { if let app { removeApp(app) } } label: { Image(systemName: "minus").frame(width: 22, height: 22) }
                    .accessibilityLabel("Remove app")
                    .disabled(app == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func sidebarRow(_ id: String?) -> some View {
        HStack(spacing: 8) {
            AppIcon(bundleID: id).frame(width: 20, height: 20)
            Text(id.map(AppNames.name) ?? "Default")
            Spacer()
            if let id, cfg.hasOwnGestures(id) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .accessibilityLabel("Has its own gestures")
            }
        }
        .opacity(id.map { cfg.targetBundleIDs.contains($0) } ?? true ? 1 : 0.45)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIcon(bundleID: app).frame(width: 32, height: 32)
                Text(app.map(AppNames.name) ?? "Default").font(.title3.weight(.semibold))
                Spacer()
                if let app {
                    Toggle("Gestures in \(AppNames.name(app))", isOn: Binding(
                        get: { appOn }, set: { ConfigEdits.setApp(app, enabled: $0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .padding(EdgeInsets(top: 18, leading: 24, bottom: 0, trailing: 24))

            Form {
                Section {
                    ForEach(cfg.rows(for: app)) { row in
                        VStack(spacing: 0) {
                            rowButton(row)
                            if model.editing == row.shape { editor(row) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(!appOn)
            .opacity(appOn ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func rowButton(_ row: GestureRow) -> some View {
        Button { model.toggle(row.shape) } label: {
            HStack(spacing: 14) {
                GestureGlyph(fingers: row.shape.fingers, type: row.shape.type, direction: row.shape.direction)
                    .frame(width: 44, height: 30)
                Text(GestureGlyph.describe(fingers: row.shape.fingers, type: row.shape.type, direction: row.shape.direction))
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                // In an app, gestures it inherits from Default are grey.
                Text(Keys.title(for: row.action))
                    .fontWeight(app == nil || row.isCustom ? .medium : .regular)
                    .foregroundStyle(app == nil || row.isCustom ? Color.primary : Color.secondary)
                if app != nil && row.isCustom {
                    Text("Custom")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                }
                Spacer()
                Text(Keys.symbols(for: row.action))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit")
    }

    // MARK: Editor

    private func editor(_ row: GestureRow) -> some View {
        // In an app, a gesture that comes from Default keeps its shape; only
        // what it does can change here. Shapes are edited in Default.
        let shapeLocked = app != nil && !row.isAppOnly
        let shape = row.shape

        return HStack(alignment: .top, spacing: 18) {
            GestureGlyph(fingers: shape.fingers, type: shape.type, direction: shape.direction)
                .padding(10)
                .frame(width: 168, height: 112)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))

            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 8) {
                    Picker("Fingers", selection: shapeField(row, \.fingers) { $0.fingers = $1 }) {
                        Text("1 finger").tag(1); Text("2 fingers").tag(2); Text("3 fingers").tag(3)
                    }
                    Picker("Motion", selection: shapeField(row, \.type) { $0.setType($1) }) {
                        Text("Tap").tag("tap"); Text("Swipe").tag("swipe")
                    }
                    Picker("Direction", selection: shapeField(row, \.direction) { $0.direction = $1 }) {
                        if shape.type == "tap" { Text("Any").tag("any") }
                        Text("←").tag("left"); Text("→").tag("right"); Text("↑").tag("up"); Text("↓").tag("down")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(shapeLocked)

                HStack(spacing: 8) {
                    actionMenu(row).frame(maxWidth: .infinity)
                    Button(model.recording ? "Type shortcut…" : "Record") {
                        model.record { setAction(row, $0) }
                    }
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    Spacer()
                    if app != nil && row.isCustom && !row.isAppOnly {
                        Button("Reset") { if let app { ConfigEdits.save(cfg.removingApp(app, shape)) } }
                            .fixedSize()
                    }
                    Button("Done") { model.toggle(shape) }
                        .keyboardShortcut(.defaultAction)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, 58)
        .padding(.vertical, 10)
    }

    private func actionMenu(_ row: GestureRow) -> some View {
        Menu {
            ForEach(Keys.menuOrder, id: \.self) { a in
                Button("\(Keys.title(for: a))    \(Keys.symbols(for: a))") { setAction(row, a) }
            }
            Divider()
            Button("Off") { setAction(row, Keys.none) }
        } label: {
            Text("\(Keys.title(for: row.action))   \(Keys.symbols(for: row.action))")
        }
    }

    /// A picker binding that edits one field of the row's shape and saves.
    private func shapeField<V>(_ row: GestureRow, _ key: KeyPath<GestureShape, V>,
                               _ set: @escaping (inout GestureShape, V) -> Void) -> Binding<V> {
        Binding(get: { row.shape[keyPath: key] }, set: { value in
            var next = row.shape
            set(&next, value)
            moveShape(row, to: next)
        })
    }

    // MARK: Actions

    private func setAction(_ row: GestureRow, _ action: String) {
        if let app {
            ConfigEdits.save(cfg.settingApp(app, row.shape, action: action))
        } else {
            ConfigEdits.save(cfg.settingDefault(row.shape, action: action))
        }
    }

    private func moveShape(_ row: GestureRow, to new: GestureShape) {
        let moved = app.map { cfg.movingAppOnly($0, row.shape, to: new) } ?? cfg.movingDefault(row.shape, to: new)
        guard let moved else { NSSound.beep(); return }     // that gesture is already in use here
        ConfigEdits.save(moved)
        model.editing = new
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        ConfigEdits.setApp(id, enabled: true)
        model.select(id)
    }

    private func removeApp(_ id: String) {
        if cfg.hasOwnGestures(id) {
            let alert = NSAlert()
            alert.messageText = "Remove \(AppNames.name(id))?"
            alert.informativeText = "Its own gestures will be deleted."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        ConfigEdits.removeApp(id)
        model.select(GesturesModel.defaultID)
    }
}

/// View-local state (a class, since @State's macro isn't available here).
final class GesturesModel: ObservableObject {
    static let defaultID = "__default"
    @Published var selection = defaultID
    @Published var editing: GestureShape?
    @Published var recording = false
    private var monitor: Any?

    func select(_ id: String) {
        selection = id
        editing = nil
        stopRecording()
    }

    func toggle(_ shape: GestureShape) {
        editing = editing == shape ? nil : shape
        stopRecording()
    }

    /// Captures the next key press as a chord; Escape cancels.
    func record(_ done: @escaping (String) -> Void) {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !(event.keyCode == 53 && mods.isEmpty),
               let chord = Keys.chord(keyCode: event.keyCode, flags: event.cgEvent?.flags ?? []) {
                done(chord)
            }
            self?.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// An app's icon, or the Default set's badge.
struct AppIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else if bundleID != nil {
            Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                .overlay(Image(systemName: "square.grid.2x2.fill").font(.system(size: 10)).foregroundStyle(.white))
                .padding(2)
        }
    }
}

/// Saving Settings edits to the config file.
enum ConfigEdits {
    static func save(_ mappings: [Mapping]) {
        let list: [[String: Any]] = mappings.map { m in
            var d: [String: Any] = ["anchor": m.anchor, "fingers": m.fingers, "type": m.type,
                                    "direction": m.direction, "action": m.action]
            if let apps = m.apps { d["apps"] = apps }
            return d
        }
        ConfigStore.shared.update(["mappings": list])
    }

    static func setApp(_ id: String, enabled: Bool) {
        let cfg = ConfigStore.shared.current
        var on = cfg.targetBundleIDs.filter { $0 != id }
        var off = cfg.disabledBundleIDs.filter { $0 != id }
        if enabled { on.append(id) } else { off.append(id) }
        ConfigStore.shared.update(["targetBundleIDs": on, "disabledBundleIDs": off.isEmpty ? nil : off])
    }

    static func removeApp(_ id: String) {
        let cfg = ConfigStore.shared.current
        var mappings = cfg.mappings
        for shape in Set(mappings.filter { $0.apps?.contains(id) == true }.map(\.shape)) {
            var c = cfg; c.mappings = mappings
            mappings = c.removingApp(id, shape)
        }
        let off = cfg.disabledBundleIDs.filter { $0 != id }
        save(mappings)
        ConfigStore.shared.update(["targetBundleIDs": cfg.targetBundleIDs.filter { $0 != id },
                                   "disabledBundleIDs": off.isEmpty ? nil : off])
    }
}
