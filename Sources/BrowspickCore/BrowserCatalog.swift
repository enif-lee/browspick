import AppKit

public struct BrowserInfo: Identifiable, Hashable, Sendable {
    public var id: String { bundleId }
    public let bundleId: String
    public let name: String
    public let path: String

    public init(bundleId: String, name: String, path: String) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
    }
}

public enum BrowserCatalog {
    /// Known browser bundle IDs → their Application Support subdirectory (Chromium family) or
    /// marker for Firefox.
    public static let known: [(bundleId: String, name: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.google.Chrome", "Chrome"),
        ("com.google.Chrome.canary", "Chrome Canary"),
        ("org.mozilla.firefox", "Firefox"),
        ("org.mozilla.firefoxdeveloperedition", "Firefox Developer Edition"),
        ("org.mozilla.nightly", "Firefox Nightly"),
        ("com.brave.Browser", "Brave"),
        ("com.brave.Browser.nightly", "Brave Nightly"),
        ("com.microsoft.edgemac", "Edge"),
        ("com.microsoft.edgemac.Dev", "Edge Dev"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.operasoftware.Opera", "Opera"),
        ("org.chromium.Chromium", "Chromium"),
        ("app.zen-browser.zen", "Zen"),
        ("net.kassett.helium", "Helium"),
        ("ai.perplexity.comet", "Comet"),
        ("com.kagi.kagimacOS", "Orion"),
    ]

    /// Browsers installed on this machine, in `known` order, plus anything else
    /// Launch Services reports as an http(s) handler.
    public static func detect() -> [BrowserInfo] {
        let ws = NSWorkspace.shared
        var result: [BrowserInfo] = []
        var seen = Set<String>()

        for (bundleId, name) in known {
            guard let url = ws.urlForApplication(withBundleIdentifier: bundleId) else { continue }
            seen.insert(bundleId)
            result.append(BrowserInfo(bundleId: bundleId, name: name, path: url.path))
        }

        // Fallback: any other registered handler for https
        if let test = URL(string: "https://example.com") {
            for url in ws.urlsForApplications(toOpen: test) {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !seen.contains(id), id != Bundle.main.bundleIdentifier else { continue }
                seen.insert(id)
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                result.append(BrowserInfo(bundleId: id, name: name, path: url.path))
            }
        }
        return result
    }

    public static func name(for bundleId: String) -> String {
        if let n = known.first(where: { $0.bundleId == bundleId })?.name { return n }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url) {
            return (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
        }
        return bundleId
    }

    public static func icon(for bundleId: String, size: CGFloat = 24) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    public static func isInstalled(_ bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
}
