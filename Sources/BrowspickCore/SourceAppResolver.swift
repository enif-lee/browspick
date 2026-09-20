import AppKit

public enum SourceAppResolver {
    /// Reads `keySenderPIDAttr` ('spid') from the GURL AppleEvent — the PID of the process
    /// that asked Launch Services to open the URL.
    /// Caveat: apps that shell out to /usr/bin/open report `open`/LaunchServices instead
    /// (the real app may have already exited). Callers should fall back to the last
    /// frontmost app in that case.
    public static func resolve(from event: NSAppleEventDescriptor) -> SourceApp? {
        guard let pidDesc = event.attributeDescriptor(forKeyword: keySenderPIDAttr) else { return nil }
        let pid = pid_t(pidDesc.int32Value)
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier else { return nil }
        // These are transport helpers, not the user's real source app.
        let meaningless: Set<String> = [
            "com.apple.launchservicesd", "com.apple.coreservices.launchservicesd",
            Bundle.main.bundleIdentifier ?? "",
        ]
        guard !meaningless.contains(bundleId) else { return nil }
        return SourceApp(bundleId: bundleId, name: app.localizedName ?? bundleId)
    }
}
