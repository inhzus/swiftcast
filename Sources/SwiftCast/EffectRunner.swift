import AppKit
import SwiftCastCore
import SwiftCastPluginKit

/// Carries out the effects plugins ask for.
@MainActor
struct EffectRunner: EffectPerforming {
    func perform(_ effect: Effect) {
        switch effect {
        case .openApplication(let url):
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .copyImage(let url):
            guard let data = try? Data(contentsOf: url) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
        case .openView:
            break  // handled by `LauncherViewModel`
        }
    }
}
