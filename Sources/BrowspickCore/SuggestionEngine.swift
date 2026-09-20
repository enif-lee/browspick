import Foundation

public enum SuggestionEngine {
    /// Groups manual picks by (patternCandidate, targetKey). A suggestion is emitted when the
    /// count reaches `threshold`, no enabled rule covers the host, and the pair isn't dismissed.
    public static func suggestions(
        records: [PickRecord],
        rules: [Rule],
        dismissed: Set<String>,
        threshold: Int
    ) -> [Suggestion] {
        var groups: [String: (pattern: String, targetKey: String, count: Int, lastSeen: Date)] = [:]
        for r in records where r.via == .manual {
            guard !r.patternCandidate.isEmpty else { continue }
            let key = "\(r.patternCandidate)|\(r.targetKey)"
            var g = groups[key] ?? (r.patternCandidate, r.targetKey, 0, .distantPast)
            g.count += 1
            g.lastSeen = max(g.lastSeen, r.timestamp)
            groups[key] = g
        }
        let engine = RuleEngine(rules: rules)
        return groups.compactMap { key, g in
            guard g.count >= threshold, !dismissed.contains(key) else { return nil }
            guard !engine.covers(host: g.pattern) else { return nil }
            return Suggestion(pattern: g.pattern, targetKey: g.targetKey,
                              evidenceCount: g.count, lastSeen: g.lastSeen)
        }
        .sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Per-profile visit counts for a host, most visited first — shown as
    /// evidence on suggestion cards.
    public static func historyHits(for pattern: String, visits: [ProfileVisits]) -> [HistoryHit] {
        visits.compactMap { v in
            guard let c = v.counts[pattern], c > 0 else { return nil }
            return HistoryHit(targetKey: v.targetKey, label: v.label, count: c)
        }
        .sorted { $0.count > $1.count }
    }

    /// Suggests rules for hosts whose visits are concentrated in one browser
    /// profile: total visits ≥ `minVisits` and the top profile holds ≥ `dominance`
    /// of them. Skips dismissed pairs and hosts already covered by a rule.
    public static func historySuggestions(
        visits: [ProfileVisits],
        rules: [Rule],
        dismissed: Set<String>,
        minVisits: Int,
        dominance: Double = 0.5
    ) -> [Suggestion] {
        // host → [(targetKey, label, count)] across every readable profile
        var byHost: [String: [(key: String, label: String, count: Int)]] = [:]
        for v in visits {
            for (host, count) in v.counts where count > 0 {
                byHost[host, default: []].append((v.targetKey, v.label, count))
            }
        }
        let engine = RuleEngine(rules: rules)
        return byHost.compactMap { host, hits in
            let total = hits.reduce(0) { $0 + $1.count }
            guard total >= minVisits, let top = hits.max(by: { $0.count < $1.count }) else { return nil }
            guard Double(top.count) / Double(total) > dominance else { return nil }
            let id = "\(host)|\(top.key)"
            guard !dismissed.contains(id), !engine.covers(host: host) else { return nil }
            return Suggestion(
                pattern: host, targetKey: top.key,
                evidenceCount: top.count, lastSeen: .now,
                source: .history,
                historyHits: hits.map { HistoryHit(targetKey: $0.key, label: $0.label, count: $0.count) }
                    .sorted { $0.count > $1.count })
        }
        .sorted { $0.evidenceCount > $1.evidenceCount }
    }
}
