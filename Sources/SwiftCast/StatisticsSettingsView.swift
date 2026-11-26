import SwiftCastCore
import SwiftCastPluginKit
import SwiftUI

/// UI state for the Statistics page, kept by `SettingsView` so it survives page switches.
@MainActor
@Observable
final class StatisticsSettingsState {
    var range = UsageStats.Range.week
    var confirmingClear = false
}

/// The Statistics page: the most used plugins, then the most used rows of each plugin that
/// keeps item statistics.
struct StatisticsSettingsView: View {
    let plugins: [any LauncherPlugin]
    /// Observable, so a use recorded while this page shows redraws it.
    let stats: UsageStats
    @Bindable var state: StatisticsSettingsState
    /// A plugin's tile color.
    let tint: (String) -> Color
    let clear: () -> Void

    var body: some View {
        let range = state.range
        let pluginsByID = Dictionary(plugins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let topPlugins = stats.topPlugins(in: range)
        let tracked = plugins.filter(\.tracksItemStatistics)
        return Form {
            Section {
                Picker("Period", selection: $state.range) {
                    ForEach(UsageStats.Range.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text("Times you ran an action on a result, by the day you ran it.")
            }

            Section("Plugins") {
                if topPlugins.isEmpty {
                    EmptyStatsText()
                }
                ForEach(topPlugins, id: \.id) { entry in
                    let plugin = pluginsByID[entry.id]
                    StatsRow(
                        title: plugin?.name ?? entry.id,
                        icon: IconTile(icon: plugin?.icon ?? .symbol("puzzlepiece.fill"),
                                       tint: tint(entry.id), size: 22),
                        count: entry.count, maxCount: topPlugins[0].count)
                }
            }

            ForEach(tracked.indices, id: \.self) { index in
                let plugin = tracked[index]
                let items = stats.topItems(pluginID: plugin.id, in: range)
                Section(plugin.name) {
                    if items.isEmpty {
                        EmptyStatsText()
                    }
                    ForEach(items, id: \.id) { entry in
                        StatsRow(
                            title: entry.title,
                            icon: IconTile(icon: entry.iconPath.map { .file($0) } ?? plugin.icon,
                                           tint: tint(plugin.id), size: 22),
                            count: entry.count, maxCount: items[0].count)
                    }
                }
            }

            Section {
                LabeledContent {
                    Button("Clear…") { state.confirmingClear = true }
                } label: {
                    Text("Statistics")
                    Text("Doesn't change how results are ranked.")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Clear statistics?", isPresented: $state.confirmingClear) {
            Button("Clear", role: .destructive, action: clear)
        } message: {
            Text("Every period's counts are forgotten.")
        }
    }
}

/// A plugin or row on the Statistics page, with a bar as long as its share of the top count.
private struct StatsRow: View {
    let title: String
    let icon: IconTile
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).lineLimit(1)
                    Spacer()
                    Text(count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(geometry.size.width * Double(count) / Double(max(maxCount, 1)), 4))
                }
                .frame(height: 4)
            }
        }
    }
}

private struct EmptyStatsText: View {
    var body: some View {
        Text("No usage in this period.").foregroundStyle(.secondary)
    }
}
