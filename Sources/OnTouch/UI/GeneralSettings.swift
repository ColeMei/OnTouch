import AppKit
import SwiftUI

/// Settings → General: config problems, permissions, startup, accident guards,
/// and where the settings file and log live.
struct GeneralSettings: View {
    @ObservedObject var status: AppStatus
    @StateObject private var model = GeneralModel()

    var body: some View {
        Form {
            if let issue = status.configIssues.first, model.dismissed != status.configIssues {
                Section { banner(issue) }
            }

            Section {
                permissionRow("Accessibility", granted: status.accessibility, pane: "Privacy_Accessibility")
                permissionRow("Input Monitoring", granted: status.inputMonitoring, pane: "Privacy_ListenEvent")
                LabeledContent("Trackpads") {
                    Text("\(status.trackpads)").foregroundStyle(status.trackpads > 0 ? Color.secondary : Color.orange)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0); model.objectWillChange.send() }))
                    .disabled(!LoginItem.isInstalled)
                Toggle("Ignore resting thumb", isOn: Binding(
                    get: { status.config.ignoresEdges },
                    set: { on in
                        let zones = ["anchorEdgeZone", "sideEdgeZone", "topEdgeZone"]
                        // Off: zero the edge strips. On: drop the keys to restore defaults.
                        ConfigStore.shared.update(Dictionary(uniqueKeysWithValues: zones.map { ($0, on ? nil : 0 as Any?) }))
                    }))
            }

            Section {
                guardSlider("Pause after typing", key: "typingGuard", value: status.config.typingGuard)
                guardSlider("Pause after scrolling", key: "scrollGuard", value: status.config.scrollGuard)
            }

            Section {
                HStack(spacing: 8) {
                    Text(ConfigStore.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Show in Finder") { Self.revealConfig() }
                    Button("Log") { NSWorkspace.shared.open(Log.url) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
    }

    // MARK: Rows

    private func banner(_ issue: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(issue).lineLimit(2).textSelection(.enabled)
            Spacer()
            Button("Show") { AppDelegate.showConfigFile() }
            Button {
                model.dismissed = status.configIssues
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
    }

    private func permissionRow(_ title: String, granted: Bool, pane: String) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Allowed", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…") { AppDelegate.openPane(pane) }
            }
        }
    }

    private func guardSlider(_ title: String, key: String, value: Double) -> some View {
        let shown = model.drafts[key] ?? value
        return LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { shown }, set: { model.drafts[key] = $0 }),
                       in: 0...1.5, step: 0.1) { editing in
                    // Save once, when the drag ends — not on every step.
                    guard !editing, let v = model.drafts[key] else { return }
                    ConfigStore.shared.update([key: (v * 10).rounded() / 10])
                    model.drafts[key] = nil
                }
                .frame(width: 180)
                Text(shown < 0.05 ? "Off" : String(format: "%.1f s", shown))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    static func revealConfig() {
        let url = URL(fileURLWithPath: ConfigStore.path)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "{\n}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// View-local state (a class, since @State's macro isn't available here).
private final class GeneralModel: ObservableObject {
    /// Slider values while dragging, by config key.
    @Published var drafts: [String: Double] = [:]
    /// The issue list the user dismissed; the banner returns if it changes.
    @Published var dismissed: [String] = []
}

extension Config {
    /// True while palm/thumb rejection is on (any edge strip in use).
    var ignoresEdges: Bool { anchorEdgeZone > 0 || sideEdgeZone > 0 || topEdgeZone > 0 }
}
