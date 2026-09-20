import AppKit

public enum Launcher {
    /// bundleId → CLI flag for private/incognito mode.
    public static let privateArgs: [String: String] = [
        "com.google.Chrome": "--incognito",
        "com.google.Chrome.canary": "--incognito",
        "com.brave.Browser": "--incognito",
        "com.brave.Browser.nightly": "--incognito",
        "com.microsoft.edgemac": "--inprivate",
        "com.microsoft.edgemac.Dev": "--inprivate",
        "org.mozilla.firefox": "-private-window",
        "org.mozilla.firefoxdeveloperedition": "-private-window",
        "org.mozilla.nightly": "-private-window",
        "company.thebrowser.Browser": "--incognito",
        "com.vivaldi.Vivaldi": "--incognito",
        "com.operasoftware.Opera": "--private",
        "org.chromium.Chromium": "--incognito",
        "app.zen-browser.zen": "-private-window",
        "ai.perplexity.comet": "--incognito",
        "net.kassett.helium": "--incognito",
    ]

    static let newWindowArgs: [String: String] = [
        "org.mozilla.firefox": "-new-window",
        "org.mozilla.firefoxdeveloperedition": "-new-window",
        "org.mozilla.nightly": "-new-window",
        "app.zen-browser.zen": "-new-window",
    ]

    /// Opens `url` in `target`. Falls back to the system default browser on failure.
    /// `background` keeps the destination app from activating (⌃-click in the picker).
    public static func launch(url: URL, target: Target, background: Bool = false, fallbackBundleId: String? = nil) {
        switch target {
        case .prompt:
            return
        case let .app(bundleId):
            launchInApp(url: url, bundleId: bundleId, background: background, fallbackBundleId: fallbackBundleId)
        case let .browser(bundleId, profile, isPrivate, newWindow):
            launchInBrowser(url: url, bundleId: bundleId, profile: profile,
                            isPrivate: isPrivate, newWindow: newWindow,
                            background: background, fallbackBundleId: fallbackBundleId)
        }
    }

    /// Command-line arguments a browser executable would get, minus the URL itself.
    /// Public for testability.
    public static func browserArgs(bundleId: String, profile: String?, isPrivate: Bool, newWindow: Bool) -> [String] {
        var args: [String] = []
        if let profile {
            // A deleted profile dir would make Chromium mint a fresh blank
            // profile — skip the flag when the catalog can verify it is gone.
            let known = ProfileCatalog.profiles(for: bundleId)
            let verified = known.isEmpty || known.contains { $0.profileArg == profile }
            if verified {
                if ProfileCatalog.isFirefox(bundleId) {
                    args += ["-P", profile]
                } else if ProfileCatalog.isChromium(bundleId) {
                    args.append("--profile-directory=\(profile)")
                }
            }
        }
        if isPrivate, let flag = privateArgs[bundleId] {
            args.append(flag)
        }
        if newWindow {
            args.append(newWindowArgs[bundleId] ?? "--new-window")
        }
        return args
    }

    private static func launchInBrowser(url: URL, bundleId: String, profile: String?,
                                        isPrivate: Bool, newWindow: Bool,
                                        background: Bool, fallbackBundleId: String?) {
        if bundleId == "com.apple.Safari" && isPrivate {
            launchSafariPrivate(url: url)
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            fallback(url: url, fallbackBundleId: fallbackBundleId)
            return
        }

        let args = browserArgs(bundleId: bundleId, profile: profile, isPrivate: isPrivate, newWindow: newWindow)

        if args.isEmpty {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !background
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if error != nil { fallback(url: url, fallbackBundleId: fallbackBundleId) }
            }
        } else {
            // NSWorkspace.openApplication drops `arguments` when the app is already
            // running, so the URL would never reach it. Spawn the executable
            // directly instead — Chromium/Firefox forward flags + URL to the
            // existing instance over IPC, honoring --profile-directory.
            if let executable = Bundle(url: appURL)?.executableURL {
                do {
                    let proc = Process()
                    proc.executableURL = executable
                    proc.arguments = args + [url.absoluteString]
                    proc.terminationHandler = { _ in }  // reap the forwarding child
                    try proc.run()
                    return
                } catch { /* fall through to workspace open */ }
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !background
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if error != nil { fallback(url: url, fallbackBundleId: fallbackBundleId) }
            }
        }
    }

    private static func launchInApp(url: URL, bundleId: String, background: Bool, fallbackBundleId: String?) {
        // Non-web schemes (zoommtg:, notion:, slack: …) resolve via Launch Services directly.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            NSWorkspace.shared.open(url)
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            fallback(url: url, fallbackBundleId: fallbackBundleId)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !background
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            if error != nil { fallback(url: url, fallbackBundleId: fallbackBundleId) }
        }
    }

    private static func fallback(url: URL, fallbackBundleId: String?) {
        // Never route back into ourselves — when Browspick is the default
        // browser, open(url) would re-trigger the picker in a loop.
        let ownURL = Bundle.main.bundleURL
        for id in [fallbackBundleId, "com.apple.Safari"].compactMap({ $0 }) {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  appURL != ownURL else { continue }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, _ in }
            return
        }
        if let resolved = NSWorkspace.shared.urlForApplication(toOpen: url), resolved != ownURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Safari has no private-mode CLI flag — drive it with AppleScript (requires Automation permission).
    private static func launchSafariPrivate(url: URL) {
        let escaped = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Safari"
                activate
                tell application "System Events"
                    keystroke "n" using {command down, shift down}
                end tell
                delay 0.5
                set URL of front document to "\(escaped)"
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            NSWorkspace.shared.open(url)
        }
    }
}
