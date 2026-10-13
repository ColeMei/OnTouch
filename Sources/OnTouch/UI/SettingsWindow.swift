import AppKit
import SwiftUI

/// The Settings window: General and Gestures tabs in a preference-style
/// toolbar. Every tab has the same fixed size, so switching never resizes it.
final class SettingsWindowController: NSWindowController {
    static let contentSize = NSSize(width: 880, height: 520)

    convenience init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab("General", symbol: "slider.horizontal.3",
                                     GeneralSettings(status: AppStatus.shared)))
        tabs.addTabViewItem(Self.tab("Gestures", symbol: "hand.tap",
                                     GesturesSettings(status: AppStatus.shared)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.setContentSize(Self.contentSize)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    private static func tab<V: View>(_ label: String, symbol: String, _ view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []                 // keep the fixed size; don't track SwiftUI's
        host.preferredContentSize = contentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    /// Menu-bar apps aren't active by default; bring the window forward.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Settings → Gestures, read-only for now: the default set, then each app's
/// own versions. Editing arrives with the sidebar layout.
struct GesturesSettings: View {
    @ObservedObject var status: AppStatus

    var body: some View {
        Form {
            section("Default", status.config.mappings.filter { $0.apps == nil })
            ForEach(appsWithOwnGestures, id: \.self) { app in
                section(AppNames.name(app), status.config.mappings.filter { $0.apps?.contains(app) == true })
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
    }

    private var appsWithOwnGestures: [String] {
        var seen: [String] = []
        for m in status.config.mappings { for a in m.apps ?? [] where !seen.contains(a) { seen.append(a) } }
        return seen
    }

    private func section(_ title: String, _ mappings: [Mapping]) -> some View {
        Section(title) {
            ForEach(Array(mappings.enumerated()), id: \.offset) { _, m in
                HStack(spacing: 14) {
                    GestureGlyph(m).frame(width: 44, height: 30)
                    Text(GestureGlyph.describe(fingers: m.fingers, type: m.type, direction: m.direction))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Text(Keys.title(for: m.action))
                    Spacer()
                    Text(Keys.symbols(for: m.action))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
