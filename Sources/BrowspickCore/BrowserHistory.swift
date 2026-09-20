import Foundation
import SQLite3

/// Visit counts for a single browser profile.
public struct ProfileVisits: Sendable, Hashable {
    /// The target matching this profile: `browser(bundleId, profile: profileArg)`.
    public let targetKey: String
    /// Display label, e.g. "Chrome — Work".
    public let label: String
    /// host (normalized, www stripped) → visit count
    public let counts: [String: Int]

    public init(targetKey: String, label: String, counts: [String: Int]) {
        self.targetKey = targetKey
        self.label = label
        self.counts = counts
    }
}

/// Reads per-profile browsing history from Chromium `History` and Firefox
/// `places.sqlite` databases. Browsers lock these files while running, so the
/// db (plus -wal/-shm) is copied to a temp directory before opening.
public enum BrowserHistory {
    private static let rowLimit: Int32 = 20_000

    /// Normalizes a URL string to the same key PickRecord.patternCandidate uses:
    /// lowercase host minus a leading "www.".
    public static func normalizeHost(_ urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Per-profile visit counts for every installed browser we can read.
    /// Profiles whose store is missing or TCC-denied are skipped silently —
    /// check `ProfileCatalog.accessStatus` to distinguish.
    public static func allVisits(supportDir: URL? = nil) -> [ProfileVisits] {
        let base = supportDir
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var out: [ProfileVisits] = []
        for (bundleId, _) in BrowserCatalog.known {
            if let sub = ProfileCatalog.chromiumDirs[bundleId] {
                let root = base.appendingPathComponent(sub)
                for profile in ProfileCatalog.profiles(for: bundleId, supportDir: supportDir) {
                    let db = root.appendingPathComponent(profile.profileArg).appendingPathComponent("History")
                    guard let counts = chromiumCounts(db: db) else { continue }
                    let browserName = BrowserCatalog.name(for: bundleId)
                    let target = Target.browser(
                        bundleId: bundleId,
                        profile: profile.profileArg == "Default" ? nil : profile.profileArg)
                    out.append(ProfileVisits(
                        targetKey: target.key,
                        label: profile.profileArg == "Default" ? browserName : "\(browserName) — \(profile.name)",
                        counts: counts))
                }
            } else if ProfileCatalog.firefoxIds.contains(bundleId) {
                let dir = bundleId == "org.mozilla.firefoxdeveloperedition"
                    ? "Firefox Developer Edition" : "Firefox"
                let root = base.appendingPathComponent(dir)
                for p in firefoxProfileDirs(ini: root.appendingPathComponent("profiles.ini"), root: root) {
                    guard let counts = firefoxCounts(db: p.url.appendingPathComponent("places.sqlite")) else { continue }
                    out.append(ProfileVisits(
                        targetKey: Target.browser(bundleId: bundleId, profile: p.name).key,
                        label: "\(BrowserCatalog.name(for: bundleId)) — \(p.name)",
                        counts: counts))
                }
            }
        }
        return out
    }

    // MARK: - Chromium

    private static func chromiumCounts(db: URL) -> [String: Int]? {
        readRows(db: db, table: "urls", urlColumn: "url", countColumn: "visit_count")
    }

    // MARK: - Firefox

    private static func firefoxCounts(db: URL) -> [String: Int]? {
        readRows(db: db, table: "moz_places", urlColumn: "url", countColumn: "visit_count")
    }

    /// profiles.ini → absolute profile directory URLs keyed by profile `Name`.
    public static func firefoxProfileDirs(ini: URL, root: URL) -> [(name: String, url: URL)] {
        guard let text = try? String(contentsOf: ini, encoding: .utf8) else { return [] }
        var result: [(name: String, url: URL)] = []
        var inProfile = false
        var name: String?, path: String?, isRelative = true

        func flush() {
            defer { name = nil; path = nil; isRelative = true }
            guard let n = name, let p = path else { return }
            let url = isRelative ? root.appendingPathComponent(p) : URL(fileURLWithPath: p)
            result.append((n, url))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") {
                flush()
                inProfile = l.hasPrefix("[Profile")
            } else if inProfile {
                let parts = l.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "Name": name = parts[1]
                case "Path": path = parts[1]
                case "IsRelative": isRelative = parts[1] != "0"
                default: break
                }
            }
        }
        flush()
        return result
    }

    // MARK: - SQLite

    /// Copies the db (+ -wal/-shm) to a temp dir so a running browser's lock
    /// doesn't block the read, then aggregates visit counts by host.
    private static func readRows(db: URL, table: String, urlColumn: String, countColumn: String) -> [String: Int]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: db.path) else { return nil }
        let tmp = fm.temporaryDirectory.appendingPathComponent("browspick-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        guard let _ = try? fm.createDirectory(at: tmp, withIntermediateDirectories: true) else { return nil }
        let copy = tmp.appendingPathComponent("db")
        do {
            try fm.copyItem(at: db, to: copy)
            for suffix in ["-wal", "-shm"] {
                let src = URL(fileURLWithPath: db.path + suffix)
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch { return nil }

        var handle: OpaquePointer?
        guard sqlite3_open(copy.path, &handle) == SQLITE_OK else { return nil }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        let sql = "SELECT \(urlColumn), \(countColumn) FROM \(table) ORDER BY last_visit_time DESC LIMIT \(rowLimit)"
        // Firefox uses a different ordering column — fall back if prepare fails.
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            sqlite3_finalize(stmt)
            let alt = "SELECT \(urlColumn), \(countColumn) FROM \(table) ORDER BY last_visit_date DESC LIMIT \(rowLimit)"
            guard sqlite3_prepare_v2(handle, alt, -1, &stmt, nil) == SQLITE_OK else { return nil }
        }
        defer { sqlite3_finalize(stmt) }

        var counts: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let urlString = String(cString: cStr)
            guard urlString.hasPrefix("http"), let host = normalizeHost(urlString) else { continue }
            counts[host, default: 0] += Int(sqlite3_column_int(stmt, 1))
        }
        return counts
    }
}
