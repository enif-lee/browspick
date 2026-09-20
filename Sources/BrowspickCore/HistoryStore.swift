import Foundation

/// Append-only JSONL history of every routed URL.
@MainActor
public final class HistoryStore {
    public static let shared = HistoryStore()

    private static let maxRecords = 1_000

    public private(set) var records: [PickRecord] = []
    private let fileURL: URL
    /// Called on the current queue after each record is appended (set by the app layer).
    public var onRecord: (() -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ConfigStore.supportDir.appendingPathComponent("history.jsonl")
        load()
    }

    public func record(_ record: PickRecord) {
        records.append(record)
        appendLine(record)
        onRecord?()
        if records.count > Self.maxRecords {
            records = Array(records.suffix(Self.maxRecords))
            rewriteFile()
        }
    }

    public func clear() {
        records = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Target key the user last picked for this URL's host, preferring records
    /// that share the longest common path prefix (host + path awareness).
    /// Manual picks only — rule-routed records don't reflect a picker choice.
    public func suggestedTargetKey(for url: URL) -> String? {
        guard let rawHost = url.host?.lowercased(), !rawHost.isEmpty else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let pathSegs = url.path.split(separator: "/").map(String.init)

        var best: (key: String, prefix: Int, date: Date)?
        for rec in records where rec.via == .manual && rec.patternCandidate == host {
            guard let recURL = URL(string: rec.url) else { continue }
            let recSegs = recURL.path.split(separator: "/").map(String.init)
            var prefix = 0
            while prefix < pathSegs.count, prefix < recSegs.count,
                  pathSegs[prefix] == recSegs[prefix] { prefix += 1 }
            // A record with a path describes a host+path pattern — it must
            // share at least one leading segment. Root-path records (host-only)
            // stay eligible for any path on the host.
            if !recSegs.isEmpty && prefix == 0 { continue }
            if let b = best, b.prefix > prefix
                || (b.prefix == prefix && b.date >= rec.timestamp) { continue }
            best = (rec.targetKey, prefix, rec.timestamp)
        }
        return best?.key
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        records = data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? dec.decode(PickRecord.self, from: Data($0))
        }
    }

    private func appendLine(_ record: PickRecord) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(record) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data("\n".utf8))
        } else {
            try? (data + Data("\n".utf8)).write(to: fileURL)
        }
    }

    private func rewriteFile() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = records.compactMap { try? enc.encode($0) }.reduce(Data()) { $0 + $1 + Data("\n".utf8) }
        try? data.write(to: fileURL, options: .atomic)
    }
}
