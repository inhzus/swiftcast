import Foundation
import SwiftCastPluginKit
@testable import SwiftCastCore

/// A plugin whose rows are set by the test, and which logs what the app tells it.
@MainActor
final class FakePlugin: LauncherPlugin {
    let id: String
    let name: String
    let summary = ""
    let icon = ResultIcon.symbol("star")
    let sectionTitle: String
    let resultLimit: Int
    var viewTitle: String?

    /// Rows for any non-blank query, unless `resultsByQuery` has the query.
    var results: [ResultItem] = []
    var resultsByQuery: [String: [ResultItem]] = [:]
    var viewRows: [ResultItem] = []
    private(set) var log: [String] = []
    private(set) var context: PluginContext?

    init(id: String, resultLimit: Int = 5, viewTitle: String? = nil) {
        self.id = id
        name = id
        sectionTitle = id
        self.resultLimit = resultLimit
        self.viewTitle = viewTitle
    }

    func activate(_ context: PluginContext) async {
        self.context = context
        log.append("activate")
    }

    func deactivate() { log.append("deactivate") }

    func results(for query: String) -> [ResultItem] {
        if let rows = resultsByQuery[query] { return rows }
        return query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : results
    }

    func viewResults(for query: String) -> [ResultItem] { viewRows }

    func didPerform(_ action: ResultAction, on item: ResultItem) {
        log.append("didPerform \(action.title) \(item.id)")
    }
}

/// Records the effects it's asked to perform, into a shared log.
@MainActor
final class RecordingEffects: EffectPerforming {
    var onPerform: (Effect) -> Void = { _ in }
    private(set) var performed: [Effect] = []

    func perform(_ effect: Effect) {
        performed.append(effect)
        onPerform(effect)
    }
}

func row(_ id: String, match: MatchQuality = .prefix, actions: [ResultAction]? = nil) -> ResultItem {
    ResultItem(
        id: id, title: id, icon: .symbol("star"),
        actions: actions ?? [ResultAction("Copy", .copy(id)), ResultAction("Copy Twice", .copy(id + id))],
        match: match)
}
