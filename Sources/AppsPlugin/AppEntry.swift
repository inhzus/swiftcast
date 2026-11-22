import Foundation

/// An installed application that can be searched and launched.
struct AppEntry: Hashable, Identifiable, Sendable {
    let name: String
    let bundleID: String?
    let url: URL
    /// Other names the app goes by (e.g. "Code" for Visual Studio Code), matched with a
    /// small penalty. Never contains `name`.
    let alternateNames: [String]
    /// The app's unlocalized name (usually English) when `name` is a translation of it, shown
    /// beside the name. `nil` when the two are the same.
    let originalName: String?
    /// `name` in pinyin when it's Chinese, so it can be typed. Worked out here, as the
    /// indexer builds entries off the main thread.
    let pinyin: PinyinReading?

    /// Stable across moves when the app has a bundle ID, so usage history follows it.
    var id: String { bundleID ?? url.path }

    init(name: String, bundleID: String?, url: URL, alternateNames: [String] = [], originalName: String? = nil) {
        self.name = name
        self.originalName = originalName == name ? nil : originalName
        self.pinyin = Pinyin.reading(of: name)
        self.bundleID = bundleID
        self.url = url
        var seen: Set<String> = [name.lowercased()]
        self.alternateNames = alternateNames.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
