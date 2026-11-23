import AppKit
import SwiftCastCore
import SwiftCastPluginKit

/// Shows and hides the launcher panel: bringing back the last search on a quick reopen,
/// opening it on a plugin's view, fading it out, and prewarming it at launch.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    /// The user asked for Settings from the panel (⌘,).
    var onSettings: () -> Void = {}

    private let settings: AppSettings
    private let host: PluginHost
    private let model: LauncherViewModel
    private let launcher: LauncherViewController
    private let panel: LauncherPanel
    /// When the panel was last hidden; a reopen soon after brings back the last search.
    private var lastHidden: Date?
    /// The panel is fading out; it's still visible until that finishes.
    private var isHiding = false

    init(settings: AppSettings, host: PluginHost, model: LauncherViewModel) {
        self.settings = settings
        self.host = host
        self.model = model
        launcher = LauncherViewController(model: model)
        panel = LauncherPanel(content: launcher.view)
        super.init()
        model.onDismiss = { [weak self] in self?.hide() }
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onSettings = { [weak self] in
            self?.hide()
            self?.onSettings()
        }
        panel.placement = settings.launcherPlacement
        panel.onPlacementChange = { [weak self] in self?.settings.launcherPlacement = $0 }
    }

    private var isShowing: Bool { panel.isVisible && !isHiding }

    func toggle() {
        if isShowing { hide() } else { show() }
    }

    /// A plugin view's hotkey: opens the panel on that view, or closes the panel when it's
    /// already showing it.
    func toggleView(_ plugin: any LauncherPlugin) {
        if isShowing {
            if model.openView?.id == plugin.id { hide() } else { model.open(plugin) }
        } else {
            show(view: plugin)
        }
    }

    /// Shows the panel: with `view`, that plugin's view; otherwise the search, brought back
    /// from last time when the panel closed recently.
    func show(view: (any LauncherPlugin)? = nil) {
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
            for plugin in self?.host.enabledPlugins ?? [] { plugin.panelDidShow() }
        }
    }

    /// Fades the panel out, then orders it out. `lastHidden` is taken now, so the restore
    /// window starts when the user dismissed the panel.
    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        lastHidden = Date()
        launcher.animateOut { [weak self] in
            self?.panel.orderOut(nil)
            self?.isHiding = false
        }
    }

    /// Runs the panel through one invisible show/type/draw cycle, so the first real open
    /// doesn't pay for one-time setup (window and layers, field editor and text input,
    /// text layout, row contents): about 55–75 ms to open and 15–30 ms for the first key.
    func prewarm() {
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()  // not key: doesn't take focus from the user's app
        launcher.prewarm()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.display()
        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self, !panel.isKeyWindow else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            launcher.prepareForShow(restoring: false)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
