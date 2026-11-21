import Foundation
import Testing
@testable import SwiftCastPluginKit

struct ShortcutTests {
    @Test func needsACommandOptionOrControlModifier() {
        #expect(Shortcut.default.isValid)
        #expect(Shortcut(keyCode: 49, modifiers: Shortcut.option).isValid)
        #expect(Shortcut(keyCode: 0, modifiers: Shortcut.control | Shortcut.shift).isValid)
        #expect(!Shortcut(keyCode: 0, modifiers: 0).isValid)
        #expect(!Shortcut(keyCode: 0, modifiers: Shortcut.shift).isValid)
    }

    @Test func functionKeysWorkAlone() {
        #expect(Shortcut(keyCode: 122, modifiers: 0).isValid)  // F1
        #expect(Shortcut(keyCode: 90, modifiers: 0).isValid)   // F20
    }

    @Test func roundTripsThroughJSON() throws {
        let shortcut = Shortcut(keyCode: 49, modifiers: Shortcut.option | Shortcut.shift)
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }
}
