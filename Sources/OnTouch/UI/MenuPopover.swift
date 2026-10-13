import AppKit
import SwiftUI

/// What the popover's buttons do; supplied by AppDelegate.
struct PopoverActions {
    var openSettings: () -> Void
    var openPrivacyPane: (String) -> Void
    var showConfigFile: () -> Void
    var quit: () -> Void
}

/// The menu-bar popover: status, the default gestures (last one used
/// highlighted), and Settings / Pause / Quit.
struct MenuPopover: View {
    @ObservedObject var status: AppStatus
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let problem = blockingProblem {
                problemRow(problem.title, button: problem.button, action: problem.action)
            } else {
                if !status.configIssues.isEmpty {
                    problemRow("Config problem", button: "Show", action: actions.showConfigFile)
                }
                gestureList
            }
            Divider().padding(.top, 8)
            footer
        }
        .frame(width: 280)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OnTouch").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Toggle("Gestures", isOn: Binding(get: { status.gesturesOn }, set: { status.setGesturesOn($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(blockingProblem != nil)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
    }

    private var statusText: String {
        if blockingProblem != nil { return "Not working" }
        if let until = status.pausedUntil {
            return "Paused until " + until.formatted(date: .omitted, time: .shortened)
        }
        if !status.gesturesOn { return "Off" }
        return AppNames.summary(status.config.targetBundleIDs)
    }

    private var statusColor: Color {
        if blockingProblem != nil { return .orange }
        return status.gesturesOn ? .green : .secondary
    }

    // MARK: Problems

    private struct Problem {
        let title: String
        let button: String?
        let action: () -> Void
    }

    /// The first thing that stops gestures from working at all.
    private var blockingProblem: Problem? {
        if !status.accessibility {
            return Problem(title: "Accessibility", button: "Allow…") { actions.openPrivacyPane("Privacy_Accessibility") }
        }
        if !status.inputMonitoring {
            return Problem(title: "Input Monitoring", button: "Allow…") { actions.openPrivacyPane("Privacy_ListenEvent") }
        }
        if status.trackpads == 0 {
            return Problem(title: "No trackpad found", button: nil) {}
        }
        return nil
    }

    private func problemRow(_ title: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13)).foregroundStyle(Color.orange.opacity(0.95))
            Spacer()
            if let button {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: Gestures

    /// The default bindings (app-specific ones live in Settings).
    private var defaults: [Mapping] {
        Array(status.config.mappings.filter { $0.apps == nil && $0.action != Keys.none }.prefix(6))
    }

    private var gestureList: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(spacing: 0) {
                ForEach(Array(defaults.enumerated()), id: \.offset) { _, m in
                    gestureRow(m, now: context.date)
                }
            }
            .padding(.horizontal, 6)
            .opacity(status.gesturesOn ? 1 : 0.45)
        }
    }

    private func gestureRow(_ m: Mapping, now: Date) -> some View {
        let recent = status.lastGesture.flatMap { g -> String? in
            guard g.action == m.action else { return nil }
            let age = now.timeIntervalSince(g.date)
            if age < 60 { return "now" }
            if age < 600 { return "\(Int(age / 60))m" }
            return nil
        }
        return HStack(spacing: 10) {
            GestureGlyph(m).frame(width: 32, height: 22)
            Text(Keys.title(for: m.action)).font(.system(size: 13))
            Spacer()
            if let recent { Text(recent).font(.system(size: 11)).foregroundStyle(Color.accentColor) }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7).fill(recent == nil ? Color.clear : Color.accentColor.opacity(0.1)))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Settings…", shortcut: "⌘,", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            if blockingProblem == nil {
                if status.pausedUntil != nil {
                    MenuRow(title: "Resume") { status.setGesturesOn(true) }
                } else if status.gesturesOn {
                    MenuRow(title: "Pause for 1 Hour") { status.pause(for: 3600) }
                }
            }
            MenuRow(title: "Quit", shortcut: "⌘Q", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
    }
}

/// A menu-style row: highlights with the accent color on hover, like NSMenu.
private struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hover.on ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(hover.on ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(hover.on ? Color.accentColor : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

/// Display names for bundle IDs.
enum AppNames {
    static func name(_ bundleID: String) -> String {
        if bundleID == "*" { return "All apps" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    /// "Google Chrome · Ghostty", or "5 apps" when the list is long.
    static func summary(_ ids: [String]) -> String {
        if ids.isEmpty || ids.contains("*") { return "All apps" }
        if ids.count > 3 { return "\(ids.count) apps" }
        return ids.map(name).joined(separator: " · ")
    }
}

/// Hover flag for MenuRow. A class with @StateObject rather than @State:
/// @State is a macro whose plugin the Command Line Tools toolchain lacks.
private final class HoverState: ObservableObject {
    @Published var on = false
}
