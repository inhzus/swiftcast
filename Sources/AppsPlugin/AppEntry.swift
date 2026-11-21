import Foundation

/// An installed application that can be searched and launched.
struct AppEntry: Hashable, Identifiable, Sendable {
    let name: String
    let bundleID: String?
    let url: URL
    /// Other names the app goes by (e.g. "Code" for Visual Studio Code), matched with a
    /// small penalty. Never contains `name`.
    let alternateNames: [String]

    /// Stable across moves when the app has a bundle ID, so usage history follows it.
    var id: String { bundleID ?? url.path }

    init(name: String, bundleID: String?, url: URL, alternateNames: [String] = []) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
        var seen: Set<String> = [name.lowercased()]
        self.alternateNames = alternateNames.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
