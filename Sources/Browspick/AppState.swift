import BrowspickCore
import Combine
import Foundation

/// Observable view-model bridging ConfigStore/HistoryStore into SwiftUI.
@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var records: [PickRecord]
    @Published var browsers: [BrowserInfo] = []
    /// Per-profile browsing-history visit counts, loaded lazily via refreshHistory().
    @Published var profileVisits: [ProfileVisits] = []

    init() {
        config = ConfigStore.shared.config
        records = HistoryStore.shared.records
        ConfigStore.shared.onChange = { [weak self] in
            self?.config = ConfigStore.shared.config
            TargetsSnapshot.write()
        }
        HistoryStore.shared.onRecord = { [weak self] in
            self?.records = HistoryStore.shared.records
        }
        browsers = BrowserCatalog.detect()
    }

    func update(_ mutate: (inout Config) -> Void) {
        ConfigStore.shared.update(mutate)
    }

    /// Reads per-profile History/places.sqlite off the main thread (db copies
    /// can be slow for heavy users), then publishes the result.
    func refreshHistory() {
        Task.detached(priority: .utility) {
            let visits = BrowserHistory.allVisits()
            await MainActor.run { [weak self] in
                self?.profileVisits = visits
            }
        }
    }

    var suggestions: [Suggestion] {
        let dismissed = Set(config.dismissedSuggestions)
        var result = SuggestionEngine.suggestions(
            records: records,
            rules: config.rules,
            dismissed: dismissed,
            threshold: config.suggestionThreshold
        )
        guard config.useBrowsingHistory else { return result }
        // Attach per-profile visit evidence to pick-based suggestions.
        for i in result.indices {
            result[i].historyHits = SuggestionEngine.historyHits(for: result[i].pattern, visits: profileVisits)
        }
        // Add history-derived suggestions not already covered by pick-based ones.
        let existing = Set(result.map(\.id))
        result += SuggestionEngine.historySuggestions(
            visits: profileVisits,
            rules: config.rules,
            dismissed: dismissed,
            minVisits: config.historyMinVisits
        ).filter { !existing.contains($0.id) }
        return result
            .filter { !isStaleTarget($0.targetKey) }
            .sorted { $0.evidenceCount != $1.evidenceCount
                ? $0.evidenceCount > $1.evidenceCount
                : $0.lastSeen > $1.lastSeen }
    }

    /// A suggestion targeting a browser profile that no longer exists
    /// (deleted since the pick) would create a rule that mints a blank
    /// profile on launch — suppress it. Unverifiable catalogs (empty list)
    /// are treated as valid.
    private func isStaleTarget(_ key: String) -> Bool {
        guard let target = Target(key: key),
              case let .browser(bundleId, profile, _, _) = target,
              let profile else { return false }
        let profiles = ProfileCatalog.profiles(for: bundleId)
        return !profiles.isEmpty && !profiles.contains { $0.profileArg == profile }
    }
}
