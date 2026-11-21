import AppKit
import Foundation
import SwiftCastPluginKit
import Testing
@testable import ClipboardPlugin

@MainActor
struct ClipboardStoreTests {
    private let folder = FileManager.default.temporaryDirectory
        .appending(path: "SwiftCastTests-\(UUID().uuidString)")
    private var images: URL { folder.appending(path: "clipboard") }

    /// A fresh connection to the same file each call, so reads after reopening come from disk.
    private func store() -> ClipboardStore {
        let database = try! Database(url: folder.appending(path: "clipboard.db"), migrations: ClipboardPlugin.migrations)
        return ClipboardStore(database: database, imageDirectory: images)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func texts(_ store: ClipboardStore) -> [String] {
        store.entries.compactMap { if case .text(let text) = $0.content { text } else { nil } }
    }

    private func imageFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []
    }

    @Test func newestFirstAndPersisted() {
        let store = store()
        store.add(.text("one"), at: now)
        store.add(.text("two"), at: now.addingTimeInterval(1))
        #expect(texts(store) == ["two", "one"])
        #expect(texts(self.store()) == ["two", "one"])
    }

    @Test func copyingAgainMovesToTop() {
        let store = store()
        store.add(.text("one"), at: now)
        store.add(.text("two"), at: now.addingTimeInterval(1))
        store.add(.text("one"), at: now.addingTimeInterval(2))
        #expect(texts(store) == ["one", "two"])
        #expect(texts(self.store()) == ["one", "two"])
    }

    @Test func keepsAtMostMaxItemsAndDeletesTheirImages() {
        let store = store()
        #expect(store.maxItems == ClipboardStore.defaultMaxItems)
        store.add(.image(Self.png(width: 2, height: 3)), at: now)
        #expect(imageFiles().count == 1)
        guard case .image(_, let width, let height) = store.entries[0].content else {
            Issue.record("not an image")
            return
        }
        #expect(width == 2 && height == 3)

        store.add(.text("a"), at: now.addingTimeInterval(1))
        store.add(.text("b"), at: now.addingTimeInterval(2))
        store.maxItems = 2
        #expect(texts(store) == ["b", "a"])
        #expect(imageFiles().isEmpty)

        store.add(.text("c"), at: now.addingTimeInterval(3))
        #expect(texts(store) == ["c", "b"])
        let reopened = self.store()
        #expect(reopened.maxItems == 2)
        #expect(texts(reopened) == ["c", "b"])
    }

    @Test func clearDeletesEverything() {
        let store = store()
        store.add(.text("a"), at: now)
        store.add(.image(Self.png(width: 1, height: 1)), at: now.addingTimeInterval(1))
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(self.store().entries.isEmpty)
        #expect(imageFiles().isEmpty)
    }

    static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
}

@MainActor
struct ClipboardPluginTests {
    private func makePlugin() -> ClipboardPlugin {
        ClipboardPlugin(
            database: .inMemory(migrations: ClipboardPlugin.migrations),
            imageDirectory: FileManager.default.temporaryDirectory.appending(path: "SwiftCastTests-\(UUID().uuidString)"))
    }

    @Test func commandRowOpensTheView() {
        let plugin = makePlugin()
        for query in ["cl", "Clip", "clipboard h", "hist"] {
            #expect(plugin.results(for: query).map(\.actions) == [[ResultAction("Open", .openView)]], "\(query)")
        }
        #expect(plugin.results(for: "hist").first?.highlightedIndices == [10, 11, 12, 13])
        for query in ["", "xyz", "board"] {
            #expect(plugin.results(for: query).isEmpty, "\(query)")
        }
    }

    @Test func viewListsAndFiltersEntries() throws {
        let plugin = makePlugin()
        plugin.add(.image(ClipboardStoreTests.png(width: 4, height: 2)))
        plugin.add(.text("\n  Hello world  \nsecond line"))
        let rows = plugin.viewResults(for: "")
        #expect(rows.map(\.title) == ["Hello world", "Image 4×2"])
        #expect(rows[0].actions == [ResultAction("Copy", .copy("\n  Hello world  \nsecond line"))])
        #expect(rows[0].preview == .text("\n  Hello world  \nsecond line"))
        let url = try #require({ if case .image(let url) = rows[1].preview { url } else { nil } }())
        #expect(rows[1].actions == [ResultAction("Copy", .copyImage(url))])
        #expect(FileManager.default.fileExists(atPath: url.path))

        #expect(plugin.viewResults(for: "SECOND").map(\.title) == ["Hello world"])
        #expect(plugin.viewResults(for: "ima").map(\.title) == ["Image 4×2"])
        #expect(plugin.viewResults(for: "nothing").isEmpty)
    }

    @Test func maxItemsSettingPrunes() {
        let plugin = makePlugin()
        for text in ["a", "b", "c"] { plugin.add(.text(text)) }
        plugin.setSetting("maxItems", to: .int(2))
        #expect(plugin.viewResults(for: "").count == 2)
        plugin.setSetting("maxItems", to: .int(0))
        #expect(plugin.store.maxItems == 1)
        #expect(plugin.settingsSections()[0].rows[0].control == .number(1, range: 1...1000))
    }

    @Test func titleIsFirstLineCut() {
        #expect(ClipboardPlugin.title(for: "  \n\t x \n y") == "x")
        let long = String(repeating: "a", count: 200)
        #expect(ClipboardPlugin.title(for: long) == String(repeating: "a", count: 120) + "…")
    }

    @Test func skipsSecretsAndFiles() {
        #expect(ClipboardMonitor.shouldRecord([.string]))
        #expect(!ClipboardMonitor.shouldRecord([]))
        #expect(!ClipboardMonitor.shouldRecord([.string, .init("org.nspasteboard.ConcealedType")]))
        #expect(!ClipboardMonitor.shouldRecord([.fileURL, .string]))
    }
}
