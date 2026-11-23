import AppKit
import SwiftCastCore
import SwiftCastPluginKit

/// Builds the app's parts and wires them together: the plugins (`PluginHost`), the launcher
/// (`LauncherViewModel`, `PanelController`), the global hotkeys (`HotKeyController`), Settings
/// and the menus.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let database = Database.open("swiftcast", migrations: AppDatabase.migrations)
    private lazy var queryHistory = QueryHistory(database: database)
    private lazy var usage = UsageStore(database: database)
    private lazy var host = PluginHost(
        plugins: PluginRegistry.makePlugins(), disabledIDs: settings.disabledPlugins, usage: usage)
    private lazy var model: LauncherViewModel = {
        let model = LauncherViewModel(host: host, history: queryHistory, usage: usage, effects: EffectRunner())
        model.measure = { name, body in PerfLog.measure(name, body) }
        return model
    }()
    private lazy var panel = PanelController(settings: settings, host: host, model: model)
    private lazy var hotKeys = HotKeyController(settings: settings, host: host, model: model)
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, plugins: host.plugins, actions: SettingsActions(
            setShortcut: { [unowned self] in hotKeys.setShortcut($0) },
            setRecording: { [unowned self] in hotKeys.setRecording($0) },
            setViewShortcut: { [unowned self] in hotKeys.setViewShortcut($0, for: $1) },
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
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerfLog.start()
        panel.onSettings = { [weak self] in self?.showSettings() }
        hotKeys.onToggle = { [weak self] in self?.panel.toggle() }
        hotKeys.onToggleView = { [weak self] in self?.panel.toggleView($0) }
        setupMainMenu()
        setupStatusItem()
        hotKeys.start()
        startPlugins()

        if CommandLine.arguments.contains("--show") {
            panel.show()
        }
        if CommandLine.arguments.contains("--settings") {
            showSettings()
        }
    }

    /// Opening the app again (e.g. `open -a SwiftCast`, or from Finder) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PerfLog.mark("reopen", eventTime: ProcessInfo.processInfo.systemUptime)
        panel.show()
        return false
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func togglePanel() {
        panel.toggle()
    }

    // MARK: - Plugins

    /// Activates the enabled plugins, renders their icons, then prewarms the panel.
    private func startPlugins() {
        host.onResultsChange = { [weak self] in self?.pluginResultsChanged() }
        settings.onPluginsChange = { [weak self] in self?.pluginsToggled() }
        Task {
            await host.start()
            model.refresh()
            await preloadIcons()
            panel.prewarm()
        }
    }

    /// A plugin was turned on or off in Settings.
    private func pluginsToggled() {
        host.setDisabled(settings.disabledPlugins)
        if let view = model.openView, !host.isEnabled(view) { model.closeView() }
        hotKeys.registerViewHotKeys()
        model.refresh()
        // Until launch has activated the plugins, that does it.
        guard host.hasStarted else { return }
        Task {
            await host.activateEnabled()
            await preloadIcons()
        }
    }

    private func pluginResultsChanged() {
        model.refresh()
        if host.hasStarted { Task { await preloadIcons() } }
    }

    private func preloadIcons() async {
        await IconCache.shared.preload(host.enabledPlugins.flatMap { $0.iconPaths() })
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open SwiftCast", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        hotKeys.openMenuItem = open
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
