import Foundation
import Testing
@testable import SwiftCastCore

struct AppIndexerTests {
    private func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SwiftCastTests-\(UUID().uuidString)")
        for path in paths {
            try FileManager.default.createDirectory(
                at: root.appending(path: path), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func findsAppsWithoutDescendingIntoBundles() throws {
        let root = try makeTree([
            "Alpha.app/Contents/MacOS",
            "Alpha.app/Contents/Helpers/Inner.app",
            "Folder/Beta.app",
            "Folder/Deeper/Gamma.app",
            "a/b/c/d/TooDeep.app",
            ".hidden/Secret.app",
            "NotAnApp",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let names = AppIndexer(roots: [root], extraApps: [], maxDepth: 3).scan().map(\.name).sorted()
        #expect(names == ["Alpha", "Beta", "Gamma"])
    }

    @Test func deduplicatesByPathAcrossRoots() throws {
        let root = try makeTree(["Alpha.app"])
        defer { try? FileManager.default.removeItem(at: root) }

        let apps = AppIndexer(roots: [root, root], extraApps: [root.appending(path: "Alpha.app")]).scan()
        #expect(apps.count == 1)
    }

    @Test func missingRootsAreIgnored() {
        let apps = AppIndexer(roots: [URL(filePath: "/nonexistent-\(UUID().uuidString)")], extraApps: []).scan()
        #expect(apps.isEmpty)
    }
}
