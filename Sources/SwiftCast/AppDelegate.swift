import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let indexer = AppIndexer()
    private let engine = SearchEngine(usage: UsageStore())
    private lazy var model = LauncherViewModel(engine: engine)
    private lazy var launcher = LauncherViewController(model: model)
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var isIndexing = false
    private var lastIndexed: Date?
    private var didPrewarm = false

    /// Rescans on panel open only when the last scan is older than this.
    private static let rescanInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerfLog.start()
        setupPanel()
        setupStatusItem()
        hotKey = HotKey(keyCode: kVK_Space, modifiers: cmdKey) { [weak self] in
            self?.togglePanel()
        }
        if hotKey == nil {
            NSLog("SwiftCast: failed to register ⌘Space hotkey (already in use?)")
        }
        reindex()

        if CommandLine.arguments.contains("--show") {
            showPanel()
        }
    }

    /// Opening the app again (e.g. `open -a SwiftCast`, or from Finder) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PerfLog.mark("reopen", eventTime: ProcessInfo.processInfo.systemUptime)
        showPanel()
        return false
    }

    // MARK: - Panel

    private func setupPanel() {
        model.onDismiss = { [weak self] in self?.hidePanel() }
        let panel = LauncherPanel(content: launcher.view)
        launcher.onHeightChange = { [unowned panel] height in panel.setHeight(height) }
        panel.setHeight(launcher.view.frame.height)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hidePanel() }
        self.panel = panel
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        // Reset and lay out before ordering front, so the first frame shown is already correct.
        launcher.prepareForShow()
        PerfLog.measure("layout") { panel.contentView?.layoutSubtreeIfNeeded() }
        panel.positionOnActiveScreen()
        // A non-activating panel can become key without activating the app, which skips an
        // activation round trip through the window server.
        PerfLog.measure("orderFront") { panel.makeKeyAndOrderFront(nil) }
        DispatchQueue.main.async { [weak self] in self?.reindex() }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    /// Runs the panel through one invisible show/type/draw cycle, so the first real open
    /// doesn't pay for one-time setup (window and layers, field editor and text input,
    /// text layout, row contents): about 55–75 ms to open and 15–30 ms for the first key.
    private func prewarm() {
        guard let panel, !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()  // not key: doesn't take focus from the user's app
        launcher.prewarm()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.display()
        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !panel.isKeyWindow else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            launcher.prepareForShow()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    // MARK: - Indexing

    private func reindex() {
        guard !isIndexing else { return }
        if let lastIndexed, Date().timeIntervalSince(lastIndexed) < Self.rescanInterval { return }
        isIndexing = true
        let indexer = indexer
        Task {
            let apps = await Task.detached(priority: .utility) { indexer.scan() }.value
            if apps != engine.apps {
                engine.update(apps: apps)
                model.refresh()
            }
            await IconCache.shared.preload(apps.map(\.url.path))
            lastIndexed = Date()
            isIndexing = false
            if !didPrewarm {
                didPrewarm = true
                prewarm()
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "SwiftCast")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open SwiftCast", action: #selector(togglePanel), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.command]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SwiftCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }
}

// MARK: - Launch at login

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let enabled = SMAppService.mainApp.status == .enabled
        for item in menu.items where item.action == #selector(toggleLaunchAtLogin(_:)) {
            item.state = enabled ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("SwiftCast: couldn't change launch at login: \(error.localizedDescription)")
        }
    }
}
