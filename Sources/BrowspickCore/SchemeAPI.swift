import Foundation

/// `browspick:` URL scheme API, modeled on Velja's:
///   browspick:open?url=<encoded>            → normal routing
///   browspick:open?url=<encoded>&prompt     → force the picker
///   browspick:open?url=...&app=<bundleId>   → force a browser/app (rules ignored)
///   browspick:open?url=...&app=<bundleId>&profile=<dir>&private&newwindow
///   browspick:open?url=...&target=<targetKey> → force an exact target; recorded
///     as a manual pick (extension popover selections feed suggestions)
public struct SchemeRequest: Sendable {
    public var url: URL
    public var target: Target?
    public var forcePrompt: Bool
    /// Forced via an explicit user choice (extension popover) — record as .manual.
    public var manualPick = false
}

public enum SchemeAPI {
    public static let scheme = "browspick"

    /// Returns nil if `url` isn't a browspick: URL or is malformed.
    /// Accepts both `browspick:open?…` (opaque, like `velja:open?…`) and `browspick://open?…`.
    public static func parse(_ url: URL) -> SchemeRequest? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let action = url.host?.lowercased() ?? url.path.lowercased()
        guard action == "open",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let raw = value("url"), let target = URL(string: raw) else { return nil }

        var forced: Target?
        var manual = false
        var prompt = items.contains { $0.name == "prompt" }
        if let key = value("target"), let t = Target(key: key) {
            forced = t
            manual = true
        } else if let bundleId = value("app") {
            if bundleId.hasPrefix("privateBrowser:") {
                forced = .browser(bundleId: String(bundleId.dropFirst("privateBrowser:".count)), isPrivate: true)
            } else {
                forced = .browser(
                    bundleId: bundleId,
                    profile: value("profile"),
                    isPrivate: items.contains { $0.name == "private" },
                    newWindow: items.contains { $0.name == "newwindow" }
                )
            }
        }
        if forced != nil { prompt = false }
        return SchemeRequest(url: target, target: forced, forcePrompt: prompt, manualPick: manual)
    }
}
