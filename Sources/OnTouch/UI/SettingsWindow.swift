import AppKit
import SwiftUI

/// The Settings window: General, Gestures and Test tabs in a preference-style
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
        tabs.addTabViewItem(Self.tab("Test", symbol: "scope",
                                     TestSettings(status: AppStatus.shared)))

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
        host.title = label                      // the window shows the selected tab's title
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
