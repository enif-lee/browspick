import Foundation

/// A ready-made rule that rewrites an https URL to a desktop app's custom scheme,
/// so e.g. zoom.us links open in Zoom instead of a browser.
public struct NativeAppPreset: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let appBundleId: String
    /// Match spec → rewrite. Rules are emitted in this order — put the most
    /// specific specs first.
    public let ruleSpecs: [RuleSpec]

    public struct RuleSpec: Hashable, Sendable {
        public var hostPatterns: [String] = []
        public var urlRegex: String?
        public var rewrite: URLRewrite?

        public init(hostPatterns: [String] = [], urlRegex: String? = nil, rewrite: URLRewrite? = nil) {
            self.hostPatterns = hostPatterns
            self.urlRegex = urlRegex
            self.rewrite = rewrite
        }
    }

    public init(name: String, appBundleId: String,
                hostPatterns: [String], rewrite: URLRewrite?,
                extraRules: [RuleSpec] = []) {
        self.name = name
        self.appBundleId = appBundleId
        self.ruleSpecs = extraRules + [RuleSpec(hostPatterns: hostPatterns, rewrite: rewrite)]
    }

    public init(name: String, appBundleId: String, ruleSpecs: [RuleSpec]) {
        self.name = name
        self.appBundleId = appBundleId
        self.ruleSpecs = ruleSpecs
    }

    public var rules: [Rule] {
        ruleSpecs.map { spec in
            var r = Rule()
            r.name = name
            r.hostPatterns = spec.hostPatterns
            r.urlRegex = spec.urlRegex
            r.rewrite = spec.rewrite
            r.target = .app(bundleId: appBundleId)
            return r
        }
    }
}

public enum NativeAppCatalog {
    public static let presets: [NativeAppPreset] = [
        // https://zoom.us/j/123?pwd=abc → zoommtg://zoom.us/join?confno=123&pwd=abc
        NativeAppPreset(
            name: "Zoom",
            appBundleId: "us.zoom.xos",
            hostPatterns: ["zoom.us"],
            rewrite: URLRewrite(
                regex: #"^https?://[^/]*zoom\.us/(?:j|my)/(\d+)[^#]*?(?:[?&]pwd=([^&#]+))?.*$"#,
                template: "zoommtg://zoom.us/join?confno=$1&pwd=$2"
            )
        ),
        // Workspace permalinks: https://acme.slack.com/archives/C456/p178… → slack://channel?id=C456
        // (subdomain URLs carry no team id; Slack falls back to the default workspace).
        // Client links: https://app.slack.com/client/T123/C456 → slack://channel?team=T123&id=C456
        NativeAppPreset(
            name: "Slack",
            appBundleId: "com.tinyspeck.slackmacgap",
            hostPatterns: ["slack.com"],
            rewrite: URLRewrite(
                regex: #"^https?://[^/]*slack\.com/(?:archives|messages)/([A-Z0-9]+)"#,
                template: "slack://channel?id=$1"
            ),
            extraRules: [
                NativeAppPreset.RuleSpec(
                    urlRegex: #"^https?://app\.slack\.com/client/[A-Z0-9]+/[A-Z0-9]+"#,
                    rewrite: URLRewrite(
                        regex: #"^https?://app\.slack\.com/client/([A-Z0-9]+)/([A-Z0-9]+)"#,
                        template: "slack://channel?team=$1&id=$2"
                    )
                ),
            ]
        ),
        // https://www.notion.so/Page-abc123 → notion://www.notion.so/Page-abc123
        NativeAppPreset(
            name: "Notion",
            appBundleId: "notion.id",
            hostPatterns: ["notion.so"],
            rewrite: URLRewrite(
                regex: #"^https?://(.*)$"#,
                template: "notion://$1"
            )
        ),
        // https://open.spotify.com/track/xyz?si=... → spotify:track:xyz
        NativeAppPreset(
            name: "Spotify",
            appBundleId: "com.spotify.client",
            hostPatterns: ["open.spotify.com"],
            rewrite: URLRewrite(
                regex: #"^https?://open\.spotify\.com/(?:intl-[a-z-]+/)?(track|album|playlist|artist|episode|show)/([A-Za-z0-9]+)"#,
                template: "spotify:$1:$2"
            )
        ),
        // https://teams.microsoft.com/l/meetup-join/... → msteams://teams.microsoft.com/l/meetup-join/...
        NativeAppPreset(
            name: "Microsoft Teams",
            appBundleId: "com.microsoft.teams2",
            hostPatterns: ["teams.microsoft.com", "teams.live.com"],
            rewrite: URLRewrite(
                regex: #"^https?://(.*)$"#,
                template: "msteams://$1"
            )
        ),
        // https://www.figma.com/design/KEY/... → figma://www.figma.com/design/KEY/...
        NativeAppPreset(
            name: "Figma",
            appBundleId: "com.figma.Desktop",
            hostPatterns: ["figma.com"],
            rewrite: URLRewrite(
                regex: #"^https?://(.*)$"#,
                template: "figma://$1"
            )
        ),
        // https://discord.com/channels/g/c → discord://discord.com/channels/g/c
        // https://discord.gg/code → discord://discord.gg/code
        NativeAppPreset(
            name: "Discord",
            appBundleId: "com.hnc.Discord",
            hostPatterns: ["discord.com"],
            rewrite: URLRewrite(
                regex: #"^https?://(?:www\.)?discord\.com/(.*)$"#,
                template: "discord://discord.com/$1"
            ),
            extraRules: [
                NativeAppPreset.RuleSpec(
                    hostPatterns: ["discord.gg"],
                    rewrite: URLRewrite(
                        regex: #"^https?://discord\.gg/(.*)$"#,
                        template: "discord://discord.gg/$1"
                    )
                ),
            ]
        ),
        // https://t.me/channel → tg://resolve?domain=channel
        // https://t.me/joinchat/x or t.me/+x → tg://join?invite=x
        NativeAppPreset(
            name: "Telegram",
            appBundleId: "ru.keepcoder.Telegram",
            hostPatterns: ["t.me"],
            rewrite: URLRewrite(
                regex: #"^https?://t\.me/([A-Za-z0-9_]+).*$"#,
                template: "tg://resolve?domain=$1"
            ),
            extraRules: [
                NativeAppPreset.RuleSpec(
                    urlRegex: #"^https?://t\.me/(?:joinchat/|\+)"#,
                    rewrite: URLRewrite(
                        regex: #"^https?://t\.me/(?:joinchat/|\+)([A-Za-z0-9_-]+)"#,
                        template: "tg://join?invite=$1"
                    )
                ),
            ]
        ),
    ]
}
