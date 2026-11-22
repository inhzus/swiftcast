import Foundation
import Testing
@testable import AppsPlugin

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

    /// A bundle named `file` whose Info.plist calls it Calculator, with `files` (relative to
    /// Contents/Resources) holding its translations.
    private func makeCalculator(file: String = "Calculator.app", _ files: [String: Data] = [:]) throws -> URL {
        let root = try makeTree([])
        let app = root.appending(path: file)
        let resources = app.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleName": "Calculator", "CFBundleIdentifier": "test.\(UUID().uuidString)"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        for (path, data) in files {
            let url = resources.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return app
    }

    private let chineseStrings = Data(#"CFBundleName = "计算器";"#.utf8)

    @Test func namesAppsInThePreferredLanguage() throws {
        let app = try makeCalculator([
            "zh-Hans.lproj/InfoPlist.strings": chineseStrings,
            "en.lproj/InfoPlist.strings": Data(#"CFBundleName = "Calculator";"#.utf8),
        ])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let chinese = AppIndexer.entry(for: app, preferredLanguages: ["zh-Hans-SG", "en-US"])
        #expect(chinese.name == "计算器")
        #expect(chinese.originalName == "Calculator")
        #expect(chinese.alternateNames.contains("Calculator"))

        let english = AppIndexer.entry(for: app, preferredLanguages: ["en-US"])
        #expect(english.name == "Calculator")
        #expect(english.originalName == nil)
    }

    @Test func readsSystemAppLoctables() throws {
        let table: [String: Any] = ["zh_CN": ["CFBundleDisplayName": "计算器"], "en": ["CFBundleName": "Calculator"]]
        let app = try makeCalculator([
            "InfoPlist.loctable": try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0),
        ])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        #expect(AppIndexer.entry(for: app, preferredLanguages: ["zh-Hans"]).name == "计算器")
    }

    @Test func keepsNamesTheUserGave() throws {
        let app = try makeCalculator(file: "MyCalc.app", ["zh-Hans.lproj/InfoPlist.strings": chineseStrings])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let entry = AppIndexer.entry(for: app, preferredLanguages: ["zh-Hans"])
        #expect(entry.name == "MyCalc")
        #expect(entry.originalName == nil)
    }

    @Test func readsPinyinInTheTranslationsLanguage() throws {
        let app = try makeCalculator([
            "ja.lproj/InfoPlist.strings": Data(#"CFBundleName = "計算機";"#.utf8),
            "zh_TW.lproj/InfoPlist.strings": Data(#"CFBundleName = "音樂";"#.utf8),
        ])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let japanese = AppIndexer.entry(for: app, preferredLanguages: ["ja-JP"])
        #expect(japanese.name == "計算機")
        #expect(japanese.pinyin.isEmpty)

        let traditional = AppIndexer.entry(for: app, preferredLanguages: ["zh-Hant-TW"])
        #expect(traditional.name == "音樂")
        #expect(traditional.pinyin.map(\.text).contains("yinyue"))
    }
}

