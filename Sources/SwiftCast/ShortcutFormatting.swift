import AppKit
import Carbon.HIToolbox
import SwiftCastCore

extension Shortcut {
    /// Builds a shortcut from a key event, with its modifiers converted to Carbon's flags.
    init(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.command) { modifiers |= Self.command }
        if flags.contains(.option) { modifiers |= Self.option }
        if flags.contains(.control) { modifiers |= Self.control }
        if flags.contains(.shift) { modifiers |= Self.shift }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers)
    }

    /// How macOS menus show it, e.g. "⌥⌘Space".
    var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + keyName
    }

    /// The key's name, or its character in the current keyboard layout.
    var keyName: String {
        if let name = Self.specialKeyNames[keyCode] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// The `keyEquivalent` string an `NSMenuItem` needs to show this shortcut, if it can.
    var menuKeyEquivalent: String? {
        switch keyCode {
        case kVK_Space: " "
        case kVK_Return: "\r"
        case kVK_Tab: "\t"
        default: Self.specialKeyNames[keyCode] == nil ? Self.character(for: keyCode) : nil
        }
    }

    private static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in fKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()

    /// The character `keyCode` types without modifiers in the current keyboard layout.
    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
