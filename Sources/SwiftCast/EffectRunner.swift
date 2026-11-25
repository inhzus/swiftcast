import AppKit
import SwiftCastCore
import SwiftCastPluginKit

/// Carries out the effects plugins ask for.
@MainActor
struct EffectRunner: EffectPerforming {
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
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .copyImage(let url):
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                Log.error("can't read image \(url.lastPathComponent) to copy (\(error))", category: "effects")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
        case .openView:
            break  // handled by `LauncherViewModel`
        }
    }
}
