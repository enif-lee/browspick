import Foundation

/// Where a matched URL should go.
public enum Target: Codable, Hashable, Sendable {
    /// profile: Chromium profile directory ("Profile 1") or Firefox profile name (-P).
    case browser(bundleId: String, profile: String? = nil, isPrivate: Bool = false, newWindow: Bool = false)
    /// Open the (possibly rewritten) URL with a specific app.
    case app(bundleId: String)
    /// Always show the picker.
    case prompt

    /// Stable string key used by history/suggestions.
    public var key: String {
        switch self {
        case let .browser(b, p, priv, nw):
            "b|\(b)|\(p ?? "-")|\(priv ? 1 : 0)|\(nw ? 1 : 0)"
        case let .app(b): "a|\(b)"
        case .prompt: "prompt"
        }
    }

    public init?(key: String) {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "b" where parts.count == 5:
            self = .browser(
                bundleId: parts[1],
                profile: parts[2] == "-" ? nil : parts[2],
                isPrivate: parts[3] == "1",
                newWindow: parts[4] == "1"
            )
        case "a" where parts.count == 2:
            self = .app(bundleId: parts[1])
        case "prompt":
            self = .prompt
        default:
            return nil
        }
    }
}

/// Regex → template URL rewrite. `$1`…`$9` are capture group references;
/// unmatched groups are replaced with an empty string.
public struct URLRewrite: Codable, Hashable, Sendable {
    public var regex: String
    public var template: String

    public init(regex: String, template: String) {
        self.regex = regex
        self.template = template
    }

    public func apply(to url: URL) -> URL? {
        let s = url.absoluteString
        guard let re = try? NSRegularExpression(pattern: regex) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return nil }
        var out = template
        for i in stride(from: m.numberOfRanges - 1, through: 1, by: -1) {
            let captured: String
            if let r = Range(m.range(at: i), in: s), m.range(at: i).location != NSNotFound {
                captured = String(s[r])
            } else {
                captured = ""
            }
            out = out.replacingOccurrences(of: "$\(i)", with: captured)
        }
        // Strip any remaining $N placeholders
        out = out.replacingOccurrences(of: #"\$\d"#, with: "", options: .regularExpression)
        return URL(string: out)
    }
}

public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name = ""
    public var enabled = true
    /// Host globs: "github.com" (matches subdomains), "*.github.com", "google.com/*" (URL glob), "*google*"
    public var hostPatterns: [String] = []
    /// Optional regex matched against the full URL (OR'd with hostPatterns)
    public var urlRegex: String?
    /// Limit to links clicked in these apps (bundle IDs). Empty = any source.
    public var sourceBundleIds: [String] = []
    /// Applied to the URL after this rule matches, before opening.
    public var rewrite: URLRewrite?
    public var target: Target = .prompt

    public init() {}
}

public struct PickRecord: Codable, Sendable {
    public enum Via: String, Codable, Sendable {
        case manual, rule, fallback
    }

    public var timestamp: Date
    public var url: String
    public var host: String
    /// Host minus a leading "www." — the unit suggestions are grouped by.
    public var patternCandidate: String
    public var sourceBundleId: String?
    public var sourceName: String?
    public var targetKey: String
    public var via: Via

    public init(timestamp: Date = .now, url: String, host: String, sourceBundleId: String?, sourceName: String?, targetKey: String, via: Via) {
        self.timestamp = timestamp
        self.url = url
        self.host = host
        self.patternCandidate = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.sourceBundleId = sourceBundleId
        self.sourceName = sourceName
        self.targetKey = targetKey
        self.via = via
    }
}

/// One browser profile's contribution to a suggestion's evidence.
public struct HistoryHit: Codable, Hashable, Sendable {
    public var targetKey: String
    /// e.g. "Chrome — Work"
    public var label: String
    public var count: Int

    public init(targetKey: String, label: String, count: Int) {
        self.targetKey = targetKey
        self.label = label
        self.count = count
    }
}

public struct Suggestion: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Generated from repeated manual picks in the picker.
        case picks
        /// Generated from per-profile browsing history dominance.
        case history
    }

    /// "pattern|targetKey"
    public var id: String
    public var pattern: String
    public var targetKey: String
    public var evidenceCount: Int
    public var lastSeen: Date
    public var source: Source = .picks
    /// Per-profile visit counts for this pattern, most visited first.
    public var historyHits: [HistoryHit] = []

    public init(pattern: String, targetKey: String, evidenceCount: Int, lastSeen: Date,
                source: Source = .picks, historyHits: [HistoryHit] = []) {
        self.pattern = pattern
        self.targetKey = targetKey
        self.evidenceCount = evidenceCount
        self.lastSeen = lastSeen
        self.source = source
        self.historyHits = historyHits
        self.id = "\(pattern)|\(targetKey)"
    }
}

public struct Config: Codable {
    public var rules: [Rule] = []
    /// Used when a target app is missing or the picker is dismissed. nil = system default.
    public var fallbackBundleId: String?
    public var stripTrackingParams = false
    public var showProfilesInPicker = true
    public var showPrivateInPicker = false
    /// Browsers hidden from the picker entirely.
    public var hiddenBundleIds: [String] = []
    /// Individual picker targets hidden by the user — Target.key strings, e.g.
    /// "b|com.google.Chrome|Profile 1|0|0" for a specific profile or private entry.
    public var hiddenPickerTargets: [String] = []
    /// Suggestion ids ("pattern|targetKey") the user dismissed — never re-suggested.
    public var dismissedSuggestions: [String] = []
    public var suggestionThreshold = 5
    /// Use per-profile browsing history (Chrome/Edge/Firefox…) to suggest rules.
    public var useBrowsingHistory = true
    /// Minimum total visits a host needs before history can suggest a rule.
    public var historyMinVisits = 5
    public var launchAtLogin = true

    public init() {}

    /// Tolerant decoding: fields added later must not break existing config.json.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        fallbackBundleId = try c.decodeIfPresent(String.self, forKey: .fallbackBundleId)
        stripTrackingParams = try c.decodeIfPresent(Bool.self, forKey: .stripTrackingParams) ?? false
        showProfilesInPicker = try c.decodeIfPresent(Bool.self, forKey: .showProfilesInPicker) ?? true
        showPrivateInPicker = try c.decodeIfPresent(Bool.self, forKey: .showPrivateInPicker) ?? false
        hiddenBundleIds = try c.decodeIfPresent([String].self, forKey: .hiddenBundleIds) ?? []
        hiddenPickerTargets = try c.decodeIfPresent([String].self, forKey: .hiddenPickerTargets) ?? []
        dismissedSuggestions = try c.decodeIfPresent([String].self, forKey: .dismissedSuggestions) ?? []
        suggestionThreshold = try c.decodeIfPresent(Int.self, forKey: .suggestionThreshold) ?? 5
        useBrowsingHistory = try c.decodeIfPresent(Bool.self, forKey: .useBrowsingHistory) ?? true
        historyMinVisits = try c.decodeIfPresent(Int.self, forKey: .historyMinVisits) ?? 5
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
    }
}

public struct SourceApp: Sendable {
    public var bundleId: String
    public var name: String

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}
