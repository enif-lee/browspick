import AppKit
import BrowspickCore
import Foundation

/// The picker target list persisted to targets.json so the native messaging
/// host — spawned under the *browser's* TCC context and unable to read other
/// browsers' profile stores — can serve the same list the picker shows.
enum TargetsSnapshot {
    /// Browspick's own support dir — not TCC-protected, so readable from the
    /// browser-spawned host too. (Can't use ConfigStore.supportDir here —
    /// it's MainActor-isolated and read() runs off-actor.)
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Browspick/targets.json")
    }

    @MainActor
    static func write() {
        let targets = Router.pickerEntries(config: ConfigStore.shared.config)
            .map(entryDict)
        guard let data = try? JSONSerialization.data(withJSONObject: ["targets": targets]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// nil when missing/empty/corrupt — caller should compute entries directly.
    static func read() -> [[String: String]]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = obj["targets"] as? [[String: String]],
              !targets.isEmpty else { return nil }
        return targets
    }

    static func entryDict(_ entry: PickerEntry) -> [String: String] {
        var d = ["key": entry.target.key, "title": entry.title]
        if let icon = entry.icon,
           let tiff = icon.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            d["icon"] = "data:image/png;base64," + png.base64EncodedString()
        }
        return d
    }
}
