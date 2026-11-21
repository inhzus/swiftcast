import AppKit
import SwiftUI

/// Owns the Settings window, created on first use and kept for later.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeView: () -> SettingsView
    private var window: NSWindow?

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // The launcher panel takes keys without activating the app, so another app is still
        // active when ⌘, arrives. The cooperative `activate()` asks that app to yield, which it
        // doesn't, leaving Settings behind it; this older call takes activation outright.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Hands focus back to the app the user came from, instead of leaving SwiftCast active
    /// with no windows.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = makeView()
        // An AppKit sidebar item is what floats the sidebar as Liquid Glass.
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Column { view.sidebar }))
        sidebar.canCollapse = false
        sidebar.minimumThickness = 210
        sidebar.maximumThickness = 210
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: Column { view.detail })))

        let window = SettingsWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // A toolbar, even an empty one, is what gives the window its Tahoe titlebar.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Size before centering: hosting controllers size the window only after layout, and
        // a window that grows after `center()` grows upward into the menu bar.
        window.setContentSize(NSSize(width: 720, height: 580))
        window.center()
        trackTitle(of: view, in: window)
        return window
    }

    /// Keeps the window title on the shown page's name, as System Settings does.
    private func trackTitle(of view: SettingsView, in window: NSWindow) {
        window.title = withObservationTracking { view.title } onChange: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                self.trackTitle(of: view, in: window)
            }
        }
    }
}

/// A split view column. Builds its content in `body`, so SwiftUI tracks what it reads there
/// and rebuilds it when that changes; passing `view.detail` itself would fix the page shown.
private struct Column<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

/// Closes on Esc, like a settings window should. The shortcut recorder gets Esc first while
/// it's recording, so there Esc only cancels the recording.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
