import AppKit
import ApplicationServices
import SwiftCastCore
import SwiftCastPluginKit

/// Carries out the effects plugins ask for.
@MainActor
struct EffectRunner: EffectPerforming {
    /// How long to wait before sending ⌘V, so the panel has faded out (0.1 s) and ordered out
    /// and the keystroke reaches the user's app instead.
    static let pasteDelay: TimeInterval = 0.15

    func perform(_ effect: Effect) {
        switch effect {
        case .openApplication(let url):
            let name = url.deletingPathExtension().lastPathComponent
            Log.info("opening \(name)", category: "effects")
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error { Log.error("can't open \(url.path) (\(error))", category: "effects") }
            }
        case .open(let url):
            if !NSWorkspace.shared.open(url) {
                // Only the scheme or the path: a web URL can carry what the user typed.
                Log.error("can't open \(url.isFileURL ? url.path : "a \(url.scheme ?? "") URL")", category: "effects")
            }
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copy(let text):
            copy(text)
        case .copyImage(let url):
            copyImage(url)
        case .paste(let text):
            copy(text)
            pasteIntoFrontApp()
        case .pasteImage(let url):
            if copyImage(url) { pasteIntoFrontApp() }
        case .openView:
            break  // handled by `LauncherViewModel`
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    private func copyImage(_ url: URL) -> Bool {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.error("can't read image \(url.lastPathComponent) to copy (\(error))", category: "effects")
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        return true
    }

    /// Sends ⌘V to the app in front once the panel is gone. The panel never activates
    /// SwiftCast, so that's the app the user was in. Posting keystrokes needs Accessibility
    /// access; without it this asks for it, and what was copied stays on the pasteboard.
    private func pasteIntoFrontApp() {
        // The value of `kAXTrustedCheckOptionPrompt`, a global var Swift 6 won't read.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Log.info("no Accessibility access; copied without pasting", category: "effects")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 9  // kVK_ANSI_V
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
