import AppKit
import BrowspickCore
import Foundation

/// Chrome native messaging host. Chromium spawns this binary as
/// `<path> chrome-extension://<id>/` — detected in main.swift before
/// NSApplication starts, so a headless stdio loop runs instead.
/// Protocol: 4-byte little-endian length + UTF-8 JSON per message.
enum NativeMessagingHost {
    static let hostName = "com.ed.browspick"
    /// Pinned by the `key` field in the extension manifest — stable across
    /// machines even when loaded unpacked.
    static let extensionID = "ccmjimgcgbbgoaelfochaljfjnadjdij"
    static let origin = "chrome-extension://\(extensionID)/"

    /// This process was spawned as a native messaging host.
    static var requested: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("chrome-extension://") }
    }

    static func run() -> Never {
        while let msg = readMessage() {
            writeMessage(handle(msg))
        }
        exit(0)
    }

    // MARK: - Messages

    private static func handle(_ msg: [String: Any]) -> [String: Any] {
        switch msg["type"] as? String {
        case "getTargets":
            return ["ok": true, "targets": targets()]
        case "send":
            guard let raw = msg["url"] as? String else { return ["ok": false] }
            var comps = URLComponents(string: "browspick:open")!
            var items = [URLQueryItem(name: "url", value: raw)]
            if let key = msg["targetKey"] as? String, !key.isEmpty {
                items.append(URLQueryItem(name: "target", value: key))
            }
            comps.queryItems = items
            guard let url = comps.url else { return ["ok": false] }
            // Delivered to the running app (or launches it) — no confirmation
            // dialog, unlike a browser-initiated external protocol navigation.
            // NSWorkspace.open() doesn't deliver from this headless spawned
            // context, so hand off through /usr/bin/open.
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = [url.absoluteString]
            do {
                try proc.run()
                proc.waitUntilExit()
                return ["ok": proc.terminationStatus == 0,
                        "openStatus": proc.terminationStatus,
                        "url": url.absoluteString]
            } catch {
                return ["ok": false]
            }
        default:
            return ["ok": false]
        }
    }

    /// The app persists the picker list to targets.json — this spawned process
    /// runs under the *browser's* TCC context and may not be able to read other
    /// browsers' profile stores, so the snapshot is the source of truth.
    private static func targets() -> [[String: String]] {
        if let snapshot = TargetsSnapshot.read() { return snapshot }
        return MainActor.assumeIsolated {
            Router.pickerEntries(config: ConfigStore.shared.config).map(TargetsSnapshot.entryDict)
        }
    }

    // MARK: - stdio framing

    private static func readMessage() -> [String: Any]? {
        guard let lenData = readFully(4) else { return nil }
        let len = Int(lenData[0]) | Int(lenData[1]) << 8
            | Int(lenData[2]) << 16 | Int(lenData[3]) << 24
        guard len > 0, len <= 1_048_576, let body = readFully(len) else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private static func readFully(_ n: Int) -> Data? {
        var data = Data()
        while data.count < n {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: n - data.count),
                  !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }

    private static func writeMessage(_ msg: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: msg) else { return }
        var len = UInt32(body.count).littleEndian
        FileHandle.standardOutput.write(Data(bytes: &len, count: 4))
        FileHandle.standardOutput.write(body)
    }

    // MARK: - Host manifest install

    /// Writes NativeMessagingHosts/com.ed.browspick.json into every installed
    /// Chromium browser's support dir — user-level path, no admin needed.
    /// Shares the app's TCC context, so Files & Folders grants apply.
    static func installManifests() {
        let host: [String: Any] = [
            "name": hostName,
            "description": "Browspick link router",
            "path": Bundle.main.executableURL!.path,
            "type": "stdio",
            "allowed_origins": [origin]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: host, options: [.prettyPrinted]) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for dir in ProfileCatalog.chromiumDirs.values {
            let browserDir = support.appendingPathComponent(dir)
            guard FileManager.default.fileExists(atPath: browserDir.path) else { continue }
            let hostsDir = browserDir.appendingPathComponent("NativeMessagingHosts")
            try? FileManager.default.createDirectory(at: hostsDir, withIntermediateDirectories: true)
            try? data.write(to: hostsDir.appendingPathComponent("\(hostName).json"))
        }
    }
}
