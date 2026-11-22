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

    /// Builds the entry for the app at `url`, named in the first of `preferredLanguages` the
    /// app is translated into. The unlocalized names stay searchable.
    static func entry(for url: URL, preferredLanguages: [String] = Locale.preferredLanguages) -> AppEntry {
        // Localized for this process, which only speaks English, so this is the English name or
        // the name the user gave the file.
        var baseName = FileManager.default.displayName(atPath: url.path)
        if baseName.hasSuffix(".app") {
            baseName = String(baseName.dropLast(4))
        }
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let displayName = Self.nonEmpty(info?["CFBundleDisplayName"])
        let bundleName = Self.nonEmpty(info?["CFBundleName"])
        let stem = url.deletingPathExtension().lastPathComponent
        let alternates = [displayName, bundleName, stem, baseName].compactMap { $0 }

        // A file the user renamed keeps that name, as in Finder.
        let renamed = ![displayName, bundleName].contains { $0?.caseInsensitiveCompare(stem) == .orderedSame }
        let localized = renamed ? nil : bundle.flatMap { localizedName(bundle: $0, preferredLanguages: preferredLanguages) }
        let name = localized?.name ?? baseName
        let translated = name != baseName
        return AppEntry(
            name: name, bundleID: bundle?.bundleIdentifier, url: url,
            alternateNames: alternates, originalName: translated ? baseName : nil,
            nameLanguage: translated ? localized?.language : nil)
    }

    /// The app's name in the first of `preferredLanguages` it's translated into, read from its
    /// `InfoPlist.strings` or, for system apps, `InfoPlist.loctable`, with the localization it
    /// came from (such as "zh_CN" or "ja").
    static func localizedName(bundle: Bundle, preferredLanguages: [String]) -> (name: String, language: String)? {
        let resources = bundle.bundleURL.appending(path: "Contents/Resources")
        let loctable = (try? Data(contentsOf: resources.appending(path: "InfoPlist.loctable")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let available = Array(Set(bundle.localizations + (loctable?.keys.filter { $0 != "LocProvenance" } ?? [])))
        guard let localization = Bundle.preferredLocalizations(from: available, forPreferences: preferredLanguages).first
        else { return nil }

        let stringsURL = resources.appending(path: "\(localization).lproj/InfoPlist.strings")
        let strings = (try? Data(contentsOf: stringsURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            ?? loctable?[localization] as? [String: Any]
        guard let name = nonEmpty(strings?["CFBundleDisplayName"]) ?? nonEmpty(strings?["CFBundleName"]) else { return nil }
        return (name, localization)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
