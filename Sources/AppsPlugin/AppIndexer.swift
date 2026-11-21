import Foundation

/// Scans well-known directories for `.app` bundles.
struct AppIndexer: Sendable {
    static let defaultRoots: [URL] = [
        URL(filePath: "/Applications"),
        URL(filePath: "/System/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]

    static let defaultExtraApps: [URL] = [
        URL(filePath: "/System/Library/CoreServices/Finder.app"),
    ]

    var roots: [URL]
    var extraApps: [URL]
    /// How many directory levels below a root are searched for apps.
    var maxDepth: Int

    init(
        roots: [URL] = AppIndexer.defaultRoots,
        extraApps: [URL] = AppIndexer.defaultExtraApps,
        maxDepth: Int = 3
    ) {
        self.roots = roots
        self.extraApps = extraApps
        self.maxDepth = maxDepth
    }

    /// Returns all apps found, de-duplicated by bundle ID (falling back to path).
    /// Earlier roots win when the same app appears more than once.
    func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var entries: [AppEntry] = []

        func add(_ url: URL) {
            let entry = Self.entry(for: url)
            let key = entry.bundleID ?? entry.url.standardizedFileURL.path
            if seen.insert(key).inserted {
                entries.append(entry)
            }
        }

        for root in roots {
            // Not `.skipsHiddenFiles`: /Applications/Safari.app is a symlink into a cryptex that
            // carries the hidden flag, so only dot-files are skipped.
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                } else if url.pathExtension == "app" {
                    enumerator.skipDescendants()
                    add(url)
                } else if enumerator.level >= maxDepth {
                    enumerator.skipDescendants()
                }
            }
        }

        for url in extraApps where fm.fileExists(atPath: url.path) {
            add(url)
        }

        return entries
    }

    static func entry(for url: URL) -> AppEntry {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let alternates = [
            info?["CFBundleDisplayName"] as? String,
            info?["CFBundleName"] as? String,
            url.deletingPathExtension().lastPathComponent,
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        return AppEntry(name: name, bundleID: bundle?.bundleIdentifier, url: url, alternateNames: alternates)
    }
}
