import AppKit
import Carbon.HIToolbox

/// Switches the keyboard input source to the one chosen for the launcher while it's open, and
/// back when it closes.
///
/// The launcher is a non-activating panel, so SwiftCast never becomes the frontmost app and
/// per-app switchers (such as Input Source Pro) never see it; this is the launcher's own rule.
@MainActor
final class InputSourceSwitcher {
    struct Option: Hashable {
        let id: String
        let title: String
    }

    /// What `end` goes back to, and the source `begin` switched to, if it did.
    private var session: (previous: TISInputSource, previousID: String, switchedTo: String?)?

    /// The enabled keyboard input sources the user can pick, by name.
    static func options() -> [Option] {
        enabledKeyboardSources().compactMap { source in
            guard let id = identifier(of: source),
                  let title: String = property(kTISPropertyLocalizedName, of: source) else { return nil }
            return Option(id: id, title: title)
        }
    }

    /// Records the current source for `end`, then switches to `preferredID` (when given and not
    /// already current) through `context`, the search field's own input context: a panel that
    /// doesn't activate its app can't change the source any other way.
    func begin(preferredID: String?, in context: NSTextInputContext?) {
        guard session == nil, let current = Self.currentSource(),
              let currentID = Self.identifier(of: current) else { return }
        var switchedTo: String?
        if let preferredID, preferredID != currentID, let context {
            context.selectedKeyboardInputSource = preferredID
            switchedTo = preferredID
        }
        session = (current, currentID, switchedTo)
    }

    /// Ends the session and returns the source the launcher closed with.
    ///
    /// With `restoringUnlessChanged`, goes back to the source from before `begin` only if it's
    /// still the one `begin` switched to: a source the user picked since stands. Without it,
    /// always goes back: whatever was picked in the launcher stays the launcher's.
    @discardableResult
    func end(restoringUnlessChanged: Bool) -> String? {
        guard let session else { return nil }
        self.session = nil
        guard let current = Self.currentSource(), let currentID = Self.identifier(of: current) else { return nil }
        let restore = restoringUnlessChanged
            ? session.switchedTo == currentID
            : currentID != session.previousID
        if restore { TISSelectInputSource(session.previous) }
        return currentID
    }

    private static func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private static func identifier(of source: TISInputSource) -> String? {
        property(kTISPropertyInputSourceID, of: source)
    }

    private static func enabledKeyboardSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.filter { source in
            property(kTISPropertyInputSourceCategory, of: source) == kTISCategoryKeyboardInputSource as String
                && property(kTISPropertyInputSourceIsSelectCapable, of: source) == true
        }
    }

    /// TIS hands back untyped pointers; a value of another type reads as absent.
    private static func property<Value>(_ key: CFString, of source: TISInputSource) -> Value? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? Value
    }
}
