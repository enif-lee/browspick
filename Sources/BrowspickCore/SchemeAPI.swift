import Foundation

/// `browspick:` URL scheme API, modeled on Velja's:
///   browspick:open?url=<encoded>            → normal routing
///   browspick:open?url=<encoded>&prompt     → force the picker
///   browspick:open?url=...&app=<bundleId>   → force a browser/app (rules ignored)
///   browspick:open?url=...&app=<bundleId>&profile=<dir>&private&newwindow
public struct SchemeRequest: Sendable {
    public var url: URL
    public var target: Target?
    public var forcePrompt: Bool
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
        var prompt = items.contains { $0.name == "prompt" }
        if let bundleId = value("app") {
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
        return SchemeRequest(url: target, target: forced, forcePrompt: prompt)
    }
}
