import AppKit
import Observation
import SwiftCastPluginKit
import SwiftUI

/// App search preferences, persisted in the `Database`.
@MainActor
@Observable
final class AppsSettings {
    @ObservationIgnored private let database: Database

    /// Folders searched for apps on top of `AppIndexer.defaultRoots`.
    var extraFolders: [URL] {
        didSet {
            database.transaction {
                database.execute("DELETE FROM search_folders")
                for (position, folder) in extraFolders.enumerated() {
                    database.execute(
                        "INSERT OR IGNORE INTO search_folders (path, position) VALUES (?, ?)",
                        [.text(folder.path), .int(Int64(position))])
                }
            }
            onFoldersChange()
        }
    }

    @ObservationIgnored var onFoldersChange: () -> Void = {}
    @ObservationIgnored var onClearLaunchHistory: () -> Void = {}

    // Settings UI state. Here rather than in `@State`, which is a macro whose plugin ships
    // only with Xcode, not the Command Line Tools this project builds with.
    var confirmingClear = false
    var historyCleared = false

    init(database: Database) {
        self.database = database
        extraFolders = database.rows("SELECT path FROM search_folders ORDER BY position")
            .compactMap { $0[0].text.map { URL(filePath: $0) } }
    }
}

/// The plugin's settings: folders searched for apps, and clearing launch history.
struct AppsSettingsView: View {
    @Bindable var settings: AppsSettings

    var body: some View {
        Section {
            ForEach(AppIndexer.defaultRoots, id: \.self) { folder in
                Label(Self.displayPath(folder), systemImage: "folder")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.extraFolders, id: \.self) { folder in
                HStack {
                    Label(Self.displayPath(folder), systemImage: "folder")
                    Spacer()
                    Button {
                        settings.extraFolders.removeAll { $0 == folder }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop searching this folder")
                }
            }
            Button("Add Folder…", action: addFolders)
        } header: {
            Text("Search Folders")
        } footer: {
            Text("Apps are found up to three folders deep.")
                .font(.callout).foregroundStyle(.secondary)
        }

        Section("Usage") {
            LabeledContent {
                Button(settings.historyCleared ? "Cleared" : "Clear…") { settings.confirmingClear = true }
                    .disabled(settings.historyCleared)
            } label: {
                Text("Launch history")
                Text("Ranks the apps you open most and lists recent ones.")
            }
            .alert("Clear launch history?", isPresented: $settings.confirmingClear) {
                Button("Clear", role: .destructive) {
                    settings.onClearLaunchHistory()
                    settings.historyCleared = true
                }
            } message: {
                Text("Recent apps and the ranking boost for frequently used apps start over.")
            }
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to search for apps"
        guard panel.runModal() == .OK else { return }
        let known = Set((AppIndexer.defaultRoots + settings.extraFolders).map(\.standardizedFileURL))
        settings.extraFolders += panel.urls.filter { !known.contains($0.standardizedFileURL) }
    }

    private static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
