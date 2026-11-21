import AppKit
import SwiftCastCore
import SwiftCastPluginKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private let plugins = PluginRegistry.makePlugins()
    private let queryHistory = QueryHistory(database: .open("swiftcast", migrations: QueryHistory.migrations))
    private lazy var model = LauncherViewModel(plugins: plugins, history: queryHistory)
    private lazy var launcher = LauncherViewController(model: model)
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, plugins: plugins, actions: SettingsActions(
            setShortcut: { [unowned self] in setShortcut($0) },
            setRecording: { [unowned self] recording in
                if recording { hotKey = nil } else { registerHotKey(settings.shortcut) }
            },
            clearSearchHistory: { [unowned self] in
                queryHistory.clear()
                model.refresh()
            }
        ))
    }
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var openMenuItem: NSMenuItem?
    private var hotKey: HotKey?
    /// The startup sequence has run; until then it preloads icons itself.
    private var didActivate = false
    /// Plugins whose `activate` has been called. A plugin that starts disabled is activated
    /// when first enabled.
    private var activatedIDs: Set<String> = []
    /// When the panel was last hidden; a reopen soon after brings back the last search.
    private var lastHidden: Date?
    /// The panel is fading out; it's still visible until that finishes.
    private var isHiding = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerfLog.start()
        setupPanel()
        setupMainMenu()
        setupStatusItem()
        if !registerHotKey(settings.shortcut) {
            NSLog("SwiftCast: failed to register \(settings.shortcut.displayString) hotkey (already in use?)")
        }
        activatePlugins()

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
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hidePanel() }
        panel.onSettings = { [weak self] in
            self?.hidePanel()
            self?.showSettings()
        }
        panel.placement = settings.launcherPlacement
        panel.onPlacementChange = { [weak self] in self?.settings.launcherPlacement = $0 }
        self.panel = panel
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible && !isHiding {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        // Reset and lay out before ordering front, so the first frame shown is already correct.
        let interval = settings.restoreInterval
        let restoring = interval > 0 && lastHidden.map { Date().timeIntervalSince($0) < interval } == true
        launcher.prepareForShow(restoring: restoring)
        PerfLog.measure("layout") { panel.contentView?.layoutSubtreeIfNeeded() }
        panel.positionOnActiveScreen()
        // A non-activating panel can become key without activating the app, which skips an
        // activation round trip through the window server.
        isHiding = false
        PerfLog.measure("orderFront") { panel.makeKeyAndOrderFront(nil) }
        launcher.animateIn()
        DispatchQueue.main.async { [weak self] in
            for plugin in self?.enabledPlugins ?? [] { plugin.panelDidShow() }
        }
    }

    /// Fades the panel out, then orders it out. `lastHidden` is taken now, so the restore
    /// window starts when the user dismissed the panel.
    private func hidePanel() {
        guard let panel, panel.isVisible, !isHiding else { return }
        isHiding = true
        lastHidden = Date()
        launcher.animateOut { [weak self] in
            panel.orderOut(nil)
            self?.isHiding = false
        }
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
            launcher.prepareForShow(restoring: false)
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

    // MARK: - Plugins

    private var enabledPlugins: [any LauncherPlugin] {
        plugins.filter { !settings.disabledPlugins.contains($0.id) }
    }

    private lazy var pluginContext = PluginContext { [weak self] in self?.pluginResultsChanged() }

    /// Activates the enabled plugins, renders their icons, then prewarms the panel.
    private func activatePlugins() {
        model.enabledIDs = Set(enabledPlugins.map(\.id))
        settings.onPluginsChange = { [weak self] in self?.pluginsToggled() }
        Task {
            for plugin in enabledPlugins { await activate(plugin) }
            model.refresh()
            await preloadIcons()
            didActivate = true
            prewarm()
        }
    }

    private func activate(_ plugin: any LauncherPlugin) async {
        guard activatedIDs.insert(plugin.id).inserted else { return }
        await plugin.activate(pluginContext)
    }

    /// A plugin was turned on or off in Settings.
    private func pluginsToggled() {
        let enabled = enabledPlugins
        model.enabledIDs = Set(enabled.map(\.id))
        model.refresh()
        guard didActivate else { return }
        Task {
            for plugin in enabled { await activate(plugin) }
            await preloadIcons()
        }
    }

    private func pluginResultsChanged() {
        model.refresh()
        if didActivate { Task { await preloadIcons() } }
    }

    private func preloadIcons() async {
        await IconCache.shared.preload(enabledPlugins.flatMap { $0.iconPaths() })
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
        item.button?.image = StatusIcon.image

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
