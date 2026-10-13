import AppKit
import ApplicationServices
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let reader = MultitouchReader()
    private let typingMonitor = TypingMonitor()
    private let scrollMonitor = ScrollMonitor()
    private let clickSuppressor = ClickSuppressor()
    private var subscriptions = Set<AnyCancellable>()
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = AppStatus.shared
        ConfigStore.shared.onChange = { status.configChanged(ConfigStore.shared) }
        ConfigStore.shared.start()
        reader.onChange = { status.setTrackpads($0) }

        setupStatusItem()
        promptForAccessibility()
        status.start()
        typingMonitor.start()
        scrollMonitor.start()
        clickSuppressor.start()
        if !reader.start() {
            Log.write("no multitouch device — check Input Monitoring permission")
        }
        observe(status)
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateIcon()

        let actions = PopoverActions(
            openSettings: { [weak self] in self?.closePopover(); self?.settings.show() },
            openPrivacyPane: { [weak self] pane in self?.closePopover(); Self.openPane(pane) },
            showConfigFile: { [weak self] in self?.closePopover(); Self.showConfigFile() },
            quit: { NSApp.terminate(nil) }
        )
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuPopover(status: AppStatus.shared, actions: actions))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() { popover.performClose(nil) }

    private func updateIcon() {
        let status = AppStatus.shared
        statusItem.button?.image = StatusIcon.image(attention: !status.isWorking,
                                                    dimmed: status.isWorking && !status.gesturesOn)
    }

    private func observe(_ status: AppStatus) {
        // objectWillChange fires before the new value lands; read it a beat later.
        status.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateIcon() } }
            .store(in: &subscriptions)

        // The event tap and multitouch access are only set up at launch, so a
        // permission granted while running needs a fresh process to take effect.
        let baseline = (ax: status.accessibility, im: status.inputMonitoring)
        status.$accessibility.combineLatest(status.$inputMonitoring)
            .dropFirst()
            .filter { ax, im in (ax && !baseline.ax) || (im && !baseline.im) }
            .first()
            .sink { [weak self] _ in self?.relaunch() }
            .store(in: &subscriptions)
    }

    private func relaunch() {
        Log.write("permission granted — relaunching to apply it")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try open.run()
            NSApp.terminate(nil)
        } catch {
            Log.write("relaunch failed: \(error)")
        }
    }

    // MARK: Helpers

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            Log.write("Accessibility permission not yet granted")
        }
    }

    static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the config file in the user's editor (creating an empty one).
    static func showConfigFile() {
        let url = URL(fileURLWithPath: ConfigStore.path)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "{\n}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
