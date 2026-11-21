import Foundation

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct Shortcut: Codable, Equatable, Sendable {
    // Carbon's modifier values (`cmdKey`, `shiftKey`, …), so Core needn't import Carbon.
    public static let command = 1 << 8
    public static let shift = 1 << 9
    public static let option = 1 << 11
    public static let control = 1 << 12

    /// ⌘Space.
    public static let `default` = Shortcut(keyCode: 49, modifiers: command)

    /// Virtual key codes of F1–F20, which work as shortcuts without a modifier.
    static let functionKeys: Set<Int> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Whether this can be a global shortcut: it needs ⌘, ⌥ or ⌃ (⇧ alone would take over
    /// ordinary typing), unless the key is an F-key.
    public var isValid: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
            || Self.functionKeys.contains(keyCode)
    }
}
