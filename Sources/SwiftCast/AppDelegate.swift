import AppKit
import SwiftCastCore
import SwiftCastPluginKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private let plugins = PluginRegistry.makePlugins()
    private let database = Database.open("swiftcast", migrations: AppDatabase.migrations)
    private lazy var queryHistory = QueryHistory(database: database)
    private lazy var usage = UsageStore(database: database)
    private lazy var model: LauncherViewModel = {
        let model = LauncherViewModel(plugins: plugins, history: queryHistory, usage: usage, effects: EffectRunner())
        model.measure = { name, body in PerfLog.measure(name, body) }
        return model
    }()
    private lazy var launcher = LauncherViewController(model: model)
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, plugins: plugins, actions: SettingsActions(
            setShortcut: { [unowned self] in setShortcut($0) },
            setRecording: { [unowned self] recording in
                if recording {
                    hotKey = nil
                    viewHotKeys = [:]
                } else {
                    registerHotKey(settings.shortcut)
                    registerViewHotKeys()
                }
            },
            setViewShortcut: { [unowned self] in setViewShortcut($0, for: $1) },
            clearSearchHistory: { [unowned self] in
                queryHistory.clear()
                model.refresh()
            },
            clearUsage: { [unowned self] in
                usage.clear()
                model.refresh()
            }
        ))
    }
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var openMenuItem: NSMenuItem?
    private var hotKey: HotKey?
    /// Hotkeys that open plugins' views, by plugin ID; only enabled plugins have one.
    private var viewHotKeys: [String: HotKey] = [:]
    /// The startup sequence has run; until then it preloads icons itself.
    private var didActivate = false
    /// Plugins whose `activate` has been called. A plugin that starts disabled is activated
    /// when enabled, and one turned off is deactivated and activated again when turned on.
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
        registerViewHotKeys()
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

    /// Shows the panel: with `view`, that plugin's view; otherwise the search, brought back
    /// from last time when the panel closed recently.
    private func showPanel(view: (any LauncherPlugin)? = nil) {
        guard let panel else { return }
        // Reset and lay out before ordering front, so the first frame shown is already correct.
        let interval = settings.restoreInterval
        let restoring = view == nil && interval > 0
            && lastHidden.map { Date().timeIntervalSince($0) < interval } == true
        launcher.prepareForShow(restoring: restoring)
        if let view { model.open(view) }
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

    /// A plugin view's hotkey: opens the panel on that view, or closes the panel when it's
    /// already showing it.
    private func toggleView(_ plugin: any LauncherPlugin) {
        guard let panel else { return }
        let isShowing = panel.isVisible && !isHiding
        if isShowing {
            if model.openView?.id == plugin.id { hidePanel() } else { model.open(plugin) }
        } else {
            showPanel(view: plugin)
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

    /// Registers `shortcut` and saves it, or returns why it can't be used; on failure the
    /// previous shortcut stays registered.
    private func setShortcut(_ shortcut: Shortcut) -> String? {
        if let plugin = plugins.first(where: { settings.viewShortcut(for: $0) == shortcut }) {
            return "\(shortcut.displayString) already opens \(plugin.viewTitle ?? plugin.name)."
        }
        guard registerHotKey(shortcut) else {
            registerHotKey(settings.shortcut)
            return "\(shortcut.displayString) is already used by another app."
        }
        settings.shortcut = shortcut
        return nil
    }

    /// Sets, or with `nil` turns off, the shortcut that opens a plugin's view, or returns why
    /// it can't be used; on failure the previous one stays.
    private func setViewShortcut(_ shortcut: Shortcut?, for pluginID: String) -> String? {
        guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return nil }
        if let shortcut {
            if shortcut == settings.shortcut {
                return "\(shortcut.displayString) already opens SwiftCast."
            }
            if let other = plugins.first(where: { $0.id != pluginID && settings.viewShortcut(for: $0) == shortcut }) {
                return "\(shortcut.displayString) already opens \(other.viewTitle ?? other.name)."
            }
        }
        if enabledPlugins.contains(where: { $0.id == pluginID }) {
            viewHotKeys[pluginID] = nil
            if let shortcut {
                guard let hotKey = makeViewHotKey(shortcut, for: plugin) else {
                    viewHotKeys[pluginID] = settings.viewShortcut(for: plugin).flatMap { makeViewHotKey($0, for: plugin) }
                    return "\(shortcut.displayString) is already used by another app."
                }
                viewHotKeys[pluginID] = hotKey
            }
        }
        // `.some`: assigning a bare `nil` would remove the entry, bringing back the default.
        settings.viewShortcuts[pluginID] = .some(shortcut)
        updateShortcutHints()
        return nil
    }

    /// Registers the view shortcuts of the enabled plugins, replacing any registered before.
    private func registerViewHotKeys() {
        viewHotKeys = [:]
        for plugin in enabledPlugins {
            guard let shortcut = settings.viewShortcut(for: plugin), shortcut != settings.shortcut else { continue }
            if let hotKey = makeViewHotKey(shortcut, for: plugin) {
                viewHotKeys[plugin.id] = hotKey
            } else {
                NSLog("SwiftCast: failed to register \(shortcut.displayString) hotkey (already in use?)")
            }
        }
        updateShortcutHints()
    }

    /// Tells the launcher which rows to label with a view shortcut.
    private func updateShortcutHints() {
        var hints: [String: String] = [:]
        for plugin in enabledPlugins {
            if let shortcut = settings.viewShortcut(for: plugin) { hints[plugin.id] = shortcut.displayString }
        }
        guard hints != model.viewShortcuts else { return }
        model.viewShortcuts = hints
        model.refresh()
    }

    private func makeViewHotKey(_ shortcut: Shortcut, for plugin: any LauncherPlugin) -> HotKey? {
        HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self, weak plugin] in
            if let plugin { self?.toggleView(plugin) }
        }
    }

    @discardableResult
    private func registerHotKey(_ shortcut: Shortcut) -> Bool {
        // Release the old hotkey first, in case it's the same combination.
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

    /// What `plugin` is offered: its rows' usage, by their IDs.
    private func context(for plugin: any LauncherPlugin) -> PluginContext {
        let pluginID = plugin.id
        return PluginContext(
            resultsDidChange: { [weak self] in self?.pluginResultsChanged() },
            usageBoost: { [unowned self] in usage.boost(for: UsageStore.Key(pluginID: pluginID, itemID: $0)) },
            importUsage: { [unowned self] in usage.import($0, for: pluginID) })
    }

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
        await plugin.activate(context(for: plugin))
    }

    /// A plugin was turned on or off in Settings.
    private func pluginsToggled() {
        let enabled = enabledPlugins
        model.enabledIDs = Set(enabled.map(\.id))
        for plugin in plugins where !model.enabledIDs.contains(plugin.id) && activatedIDs.contains(plugin.id) {
            plugin.deactivate()
            activatedIDs.remove(plugin.id)
        }
        if let view = model.openView, !model.enabledIDs.contains(view.id) { model.closeView() }
        registerViewHotKeys()
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
