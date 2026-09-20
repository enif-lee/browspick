import AppKit
import BrowspickCore

// Debug: `Browspick --dump-profiles` writes Chromium Local State details to
// profiles-dump.txt (needs the app's own TCC context — `browspick:dump` works too).
if CommandLine.arguments.contains("--dump-profiles") {
    try? ProfileCatalog.debugDump().write(
        to: ConfigStore.supportDir.appendingPathComponent("profiles-dump.txt"),
        atomically: true, encoding: .utf8)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
