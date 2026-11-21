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
        let window = SettingsWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "SwiftCast Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

/// Closes on Esc, like a settings window should. The shortcut recorder gets Esc first while
/// it's recording, so there Esc only cancels the recording.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
