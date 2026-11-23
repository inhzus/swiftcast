import AppKit
import SwiftCastCore
import SwiftCastPluginKit

/// The global hotkeys: the one that toggles the launcher, and those that open enabled
/// plugins' views. Validates and saves the shortcuts the user picks in Settings.
@MainActor
final class HotKeyController {
    var onToggle: () -> Void = {}
    var onToggleView: (any LauncherPlugin) -> Void = { _ in }
    /// The status menu's "Open SwiftCast" item, which shows the launcher shortcut.
    var openMenuItem: NSMenuItem? {
        didSet { updateOpenMenuItem() }
    }

    private let settings: AppSettings
    private let host: PluginHost
    private let model: LauncherViewModel
    private var hotKey: HotKey?
    /// Hotkeys that open plugins' views, by plugin ID; only enabled plugins have one.
    private var viewHotKeys: [String: HotKey] = [:]

    init(settings: AppSettings, host: PluginHost, model: LauncherViewModel) {
        self.settings = settings
        self.host = host
        self.model = model
    }

    /// Registers the saved shortcuts.
    func start() {
        if !registerHotKey(settings.shortcut) {
            NSLog("SwiftCast: failed to register \(settings.shortcut.displayString) hotkey (already in use?)")
        }
        registerViewHotKeys()
    }

    /// While the Settings recorder listens, every hotkey is released so it can be recorded.
    func setRecording(_ recording: Bool) {
        if recording {
            hotKey = nil
            viewHotKeys = [:]
        } else {
            registerHotKey(settings.shortcut)
            registerViewHotKeys()
        }
    }

    /// Registers `shortcut` and saves it, or returns why it can't be used; on failure the
    /// previous shortcut stays registered.
    func setShortcut(_ shortcut: Shortcut) -> String? {
        if let conflict = conflict(of: shortcut, for: .launcher) { return conflict }
        guard registerHotKey(shortcut) else {
            registerHotKey(settings.shortcut)
            return "\(shortcut.displayString) is already used by another app."
        }
        settings.shortcut = shortcut
        return nil
    }

    /// Sets, or with `nil` turns off, the shortcut that opens a plugin's view, or returns why
    /// it can't be used; on failure the previous one stays.
    func setViewShortcut(_ shortcut: Shortcut?, for pluginID: String) -> String? {
        guard let plugin = host.plugin(id: pluginID) else { return nil }
        if let shortcut, let conflict = conflict(of: shortcut, for: .view(pluginID: pluginID)) {
            return conflict
        }
        if host.isEnabled(plugin) {
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
    func registerViewHotKeys() {
        viewHotKeys = [:]
        for plugin in host.enabledPlugins {
            guard let shortcut = settings.viewShortcut(for: plugin), shortcut != settings.shortcut else { continue }
            if let hotKey = makeViewHotKey(shortcut, for: plugin) {
                viewHotKeys[plugin.id] = hotKey
            } else {
                NSLog("SwiftCast: failed to register \(shortcut.displayString) hotkey (already in use?)")
            }
        }
        updateShortcutHints()
    }

    /// Why `shortcut` can't be given to `target`, as shown in Settings.
    private func conflict(of shortcut: Shortcut, for target: ShortcutTarget) -> String? {
        var views: [String: Shortcut] = [:]
        for plugin in host.plugins {
            views[plugin.id] = settings.viewShortcut(for: plugin)
        }
        switch ShortcutRules.conflict(of: shortcut, for: target, launcher: settings.shortcut, views: views) {
        case nil:
            return nil
        case .launcher:
            return "\(shortcut.displayString) already opens SwiftCast."
        case .view(let pluginID):
            let plugin = host.plugin(id: pluginID)
            return "\(shortcut.displayString) already opens \(plugin?.viewTitle ?? plugin?.name ?? pluginID)."
        }
    }

    /// Tells the launcher which rows to label with a view shortcut.
    private func updateShortcutHints() {
        var hints: [String: String] = [:]
        for plugin in host.enabledPlugins {
            if let shortcut = settings.viewShortcut(for: plugin) { hints[plugin.id] = shortcut.displayString }
        }
        guard hints != model.viewShortcuts else { return }
        model.viewShortcuts = hints
        model.refresh()
    }

    private func makeViewHotKey(_ shortcut: Shortcut, for plugin: any LauncherPlugin) -> HotKey? {
        HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self, weak plugin] in
            if let plugin { self?.onToggleView(plugin) }
        }
    }

    @discardableResult
    private func registerHotKey(_ shortcut: Shortcut) -> Bool {
        // Release the old hotkey first, in case it's the same combination.
        hotKey = nil
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.onToggle()
        }
        updateOpenMenuItem(shortcut)
        return hotKey != nil
    }

    private func updateOpenMenuItem(_ shortcut: Shortcut? = nil) {
        guard let item = openMenuItem else { return }
        let shortcut = shortcut ?? settings.shortcut
        item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }
}
