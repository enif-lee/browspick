import Foundation

public enum PatternMatcher {
    /// Pattern semantics:
    /// - contains "/"        → glob matched against the full URL string
    /// - contains "*"        → glob matched against the host
    /// - otherwise           → host == pattern, or host is a subdomain of pattern
    public static func hostMatches(pattern rawPattern: String, host rawHost: String, url: URL) -> Bool {
        let pattern = rawPattern.lowercased()
        let host = rawHost.lowercased()
        guard !pattern.isEmpty, !host.isEmpty else { return false }
        if pattern.contains("/") {
            // URL globs match "host/path?query" (scheme stripped) so "google.com/maps/*" works.
            var target = host + url.path
            if let q = url.query { target += "?" + q }
            return glob(pattern, matches: target)
        }
        if pattern.contains("*") {
            return glob(pattern, matches: host)
        }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// `*` matches any run of characters; everything else is literal. Case-insensitive.
    public static func glob(_ globPattern: String, matches value: String) -> Bool {
        var re = NSRegularExpression.escapedPattern(for: globPattern.lowercased())
        re = re.replacingOccurrences(of: "\\*", with: ".*")
        return value.lowercased().range(of: "^\(re)$", options: .regularExpression) != nil
    }
}
