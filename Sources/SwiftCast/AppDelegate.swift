import AppKit
import SwiftCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private let engine = SearchEngine(usage: UsageStore())
    private lazy var model = LauncherViewModel(engine: engine)
    private lazy var launcher = LauncherViewController(model: model)
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, actions: SettingsActions(
            setShortcut: { [unowned self] in setShortcut($0) },
            setRecording: { [unowned self] recording in
                if recording { hotKey = nil } else { registerHotKey(settings.shortcut) }
            },
            clearHistory: { [unowned self] in
                engine.usage.clear()
                model.refresh()
            }
        ))
    }
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var openMenuItem: NSMenuItem?
    private var hotKey: HotKey?
    private var isIndexing = false
    /// Set when the search folders change mid-scan, so another scan follows.
    private var needsReindex = false
    private var lastIndexed: Date?
    private var didPrewarm = false

    /// Rescans on panel open only when the last scan is older than this.
    private static let rescanInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerfLog.start()
        setupPanel()
        setupMainMenu()
        setupStatusItem()
        if !registerHotKey(settings.shortcut) {
            NSLog("SwiftCast: failed to register \(settings.shortcut.displayString) hotkey (already in use?)")
        }
        settings.onFoldersChange = { [weak self] in
            self?.lastIndexed = nil
            self?.reindex()
        }
        reindex()

        if CommandLine.arguments.contains("--show") {
            showPanel()
        }
        if CommandLine.arguments.contains("--settings") {
            showSettings()
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
        panel.onSettings = { [weak self] in
            self?.hidePanel()
            self?.showSettings()
        }
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

    // MARK: - Hotkey and settings

    @objc private func showSettings() {
        settingsWindow.show()
    }

    /// Registers `shortcut` and saves it; on failure the previous shortcut stays registered.
    private func setShortcut(_ shortcut: Shortcut) -> Bool {
        guard registerHotKey(shortcut) else {
            registerHotKey(settings.shortcut)
            return false
        }
        settings.shortcut = shortcut
        return true
    }

    @discardableResult
    private func registerHotKey(_ shortcut: Shortcut) -> Bool {
        // Release the old hotkey first: its handler fires for any SwiftCast hotkey.
        hotKey = nil
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.togglePanel()
        }
        updateOpenMenuItem(shortcut)
        return hotKey != nil
    }

    private func updateOpenMenuItem(_ shortcut: Shortcut) {
        guard let item = openMenuItem else { return }
        item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers & Shortcut.command != 0 { mask.insert(.command) }
        if shortcut.modifiers & Shortcut.option != 0 { mask.insert(.option) }
        if shortcut.modifiers & Shortcut.control != 0 { mask.insert(.control) }
        if shortcut.modifiers & Shortcut.shift != 0 { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }

    // MARK: - Indexing

    private var indexer: AppIndexer {
        AppIndexer(roots: AppIndexer.defaultRoots + settings.extraFolders)
    }

    private func reindex() {
        guard !isIndexing else {
            needsReindex = true
            return
        }
        if let lastIndexed, Date().timeIntervalSince(lastIndexed) < Self.rescanInterval { return }
        isIndexing = true
        needsReindex = false
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
            if needsReindex {
                lastIndexed = nil
                reindex()
            } else if !didPrewarm {
                didPrewarm = true
                prewarm()
            }
        }
    }

    // MARK: - Menus

    /// The menu bar shown while SwiftCast is active, i.e. while Settings is open. It's what
    /// gives that window ⌘W, ⌘Q, ⌘, and the edit shortcuts.
    private func setupMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit SwiftCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for menu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "SwiftCast")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open SwiftCast", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openMenuItem = open
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SwiftCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }
}
