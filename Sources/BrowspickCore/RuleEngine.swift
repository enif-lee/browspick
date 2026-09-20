import Foundation

public struct RuleEngine: Sendable {
    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// First enabled rule whose matchers all pass wins.
    /// Within a rule, hostPatterns and urlRegex are OR'd; sourceBundleIds is a gate.
    public func match(url: URL, sourceBundleId: String?) -> Rule? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        for rule in rules where rule.enabled {
            if !rule.sourceBundleIds.isEmpty {
                guard let source = sourceBundleId,
                      rule.sourceBundleIds.contains(source) else { continue }
            }
            let hasHost = rule.hostPatterns.contains { $0.isEmpty == false }
            let hasRegex = rule.urlRegex?.isEmpty == false
            guard hasHost || hasRegex else { continue }

            let hostOK = rule.hostPatterns.contains { PatternMatcher.hostMatches(pattern: $0, host: host, url: url) }
            let regexOK = rule.urlRegex.flatMap { r in
                r.isEmpty ? nil : url.absoluteString.range(of: r, options: .regularExpression)
            } != nil
            if hostOK || regexOK { return rule }
        }
        return nil
    }

    /// True if an enabled rule would auto-route URLs on this host (used to suppress stale suggestions).
    public func covers(host: String, sourceBundleId: String? = nil) -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        return match(url: url, sourceBundleId: sourceBundleId) != nil
    }
}
