import Foundation

public struct BrowserProfile: Hashable, Sendable, Identifiable {
    public var id: String { "\(browserBundleId)|\(profileArg)" }
    public let browserBundleId: String
    /// Value passed on the command line: profile directory for Chromium, profile name for Firefox.
    public let profileArg: String
    /// Human-readable profile name.
    public let name: String
    /// Local avatar image ("<Product> Profile Picture.png" in the profile dir), if any.
    public var pictureURL: URL?

    public init(browserBundleId: String, profileArg: String, name: String, pictureURL: URL? = nil) {
        self.browserBundleId = browserBundleId
        self.profileArg = profileArg
        self.name = name
        self.pictureURL = pictureURL
    }
}

public enum ProfileCatalog {
    /// bundleId → directory under ~/Library/Application Support containing "Local State".
    public static let chromiumDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "org.chromium.Chromium": "Chromium",
        "ai.perplexity.comet": "Perplexity/Comet",
        "net.kassett.helium": "net.imput.helium",
        "company.thebrowser.Browser": "Arc/User Data",
    ]

    public static let firefoxIds: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
    ]

    public static func isChromium(_ bundleId: String) -> Bool {
        chromiumDirs.keys.contains(bundleId)
    }

    public static func isFirefox(_ bundleId: String) -> Bool {
        firefoxIds.contains(bundleId)
    }

    /// Whether reading a browser's profile store is allowed. Modern macOS protects
    /// other apps' data under ~/Library/Application Support via TCC — reads return
    /// EPERM until the user grants Browspick access under Privacy & Security →
    /// Files & Folders (or Full Disk Access).
    public enum ProfileAccess: Sendable {
        /// File readable (or absent — no profiles to read anyway).
        case granted
        /// File exists but reading was denied by TCC.
        case denied
        /// Browser has no known profile store.
        case notApplicable
    }

    /// The file holding the profile list: Chromium "Local State" or Firefox "profiles.ini".
    public static func profileStoreURL(for bundleId: String, supportDir: URL? = nil) -> URL? {
        let base = supportDir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let sub = chromiumDirs[bundleId] {
            return base.appendingPathComponent(sub).appendingPathComponent("Local State")
        }
        if firefoxIds.contains(bundleId) {
            let dir = bundleId == "org.mozilla.firefoxdeveloperedition"
                ? "Firefox Developer Edition" : "Firefox"
            return base.appendingPathComponent(dir).appendingPathComponent("profiles.ini")
        }
        return nil
    }

    public static func accessStatus(for bundleId: String, supportDir: URL? = nil) -> ProfileAccess {
        guard let file = profileStoreURL(for: bundleId, supportDir: supportDir) else { return .notApplicable }
        guard FileManager.default.fileExists(atPath: file.path) else { return .granted }
        return (try? Data(contentsOf: file)) != nil ? .granted : .denied
    }

    /// Debug dump of every known profile store: access state, last_used,
    /// raw info_cache fields and on-disk directory existence. Written via the
    /// app (which holds the TCC grant) — `browspick:dump` or `--dump-profiles`.
    public static func debugDump() -> String {
        var out = ""
        for id in chromiumDirs.keys.sorted() + firefoxIds.sorted() {
            guard let url = profileStoreURL(for: id) else { continue }
            out += "=== \(id) ===\n"
            out += "access: \(accessStatus(for: id))\n"
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let profile = json["profile"] as? [String: Any] {
                out += "last_used: \(profile["last_used"] ?? "<none>")\n"
                out += "last_active_profiles: \(profile["last_active_profiles"] ?? "<none>")\n"
                if let cache = profile["info_cache"] as? [String: [String: Any]] {
                    for (dir, info) in cache.sorted(by: { $0.key < $1.key }) {
                        let exists = FileManager.default.fileExists(
                            atPath: url.deletingLastPathComponent().appendingPathComponent(dir).path)
                        let fields = info.sorted { $0.key < $1.key }
                            .compactMap { k, v in
                                ["name", "gaia_name", "user_name", "gaia_given_name",
                                 "shortcut_name", "is_using_default_name", "gaia_id"].contains(k)
                                    ? "\(k)=\(v)" : nil
                            }
                            .joined(separator: "  ")
                        out += "  [\(dir)] dirExists=\(exists)  \(fields)\n"
                    }
                }
            } else {
                out += "(store unreadable)\n"
            }
        }
        return out
    }

    /// Enumerates profiles for a browser. Reading `~/Library/Application Support/<Browser>/Local State`
    /// may trigger the macOS "Files & Folders" permission prompt.
    public static func profiles(for bundleId: String, supportDir: URL? = nil) -> [BrowserProfile] {
        let base = supportDir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let sub = chromiumDirs[bundleId] {
            return chromiumProfiles(base: base.appendingPathComponent(sub), bundleId: bundleId)
        }
        if firefoxIds.contains(bundleId) {
            let dir = bundleId == "org.mozilla.firefoxdeveloperedition"
                ? "Firefox Developer Edition" : "Firefox"
            return firefoxProfiles(base: base.appendingPathComponent(dir), bundleId: bundleId)
        }
        return []
    }

    /// Parses the `profile.info_cache` object of a Chromium "Local State" file.
    /// Exposed for testing: `localState` is the file's JSON bytes.
    public static func parseLocalState(_ data: Data, bundleId: String) -> [BrowserProfile] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        return cache.compactMap { dir, info in
            guard let dict = info as? [String: Any] else { return nil }
            return BrowserProfile(browserBundleId: bundleId, profileArg: dir, name: Self.profileName(dir: dir, info: dict))
        }
        .sorted { $0.profileArg.localizedCompare($1.profileArg) == .orderedAscending }
    }

    /// Picks the most useful display name from a Chromium info_cache entry.
    /// Recent Chrome versions store unsigned profiles as literal "Profile N",
    /// so fall back to the account name/email when the name is generic.
    static func profileName(dir: String, info: [String: Any]) -> String {
        let name = (info["name"] as? String) ?? ""
        let account = (info["gaia_name"] as? String)
            ?? (info["user_name"] as? String)
            ?? (info["gaia_given_name"] as? String)
        let generic = name.isEmpty
            || name.range(of: #"^Profile \d+$"#, options: .regularExpression) != nil
        if generic, let account, !account.isEmpty { return account }
        if !name.isEmpty { return name }
        return dir
    }

    /// Parses Firefox `profiles.ini` contents. Returns profiles keyed by their `Name=`
    /// (what `-P` expects), skipping the special "default"/install sections.
    public static func parseProfilesINI(_ text: String, bundleId: String) -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []
        var inProfile = false
        var name: String?

        func flush() {
            if let n = name {
                profiles.append(BrowserProfile(browserBundleId: bundleId, profileArg: n, name: n))
            }
            name = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("[") {
                flush()
                inProfile = l.hasPrefix("[Profile")
            } else if inProfile {
                let parts = l.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == "Name" {
                    name = parts[1]
                }
            }
        }
        flush()
        return profiles
    }

    private static func chromiumProfiles(base: URL, bundleId: String) -> [BrowserProfile] {
        let localState = base.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState) else { return [] }
        // info_cache can retain entries for profiles whose directory was deleted —
        // launching those would make Chromium recreate a fresh empty profile.
        return parseLocalState(data, bundleId: bundleId).compactMap { profile in
            let dir = base.appendingPathComponent(profile.profileArg)
            guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
            var p = profile
            p.pictureURL = avatarFile(in: dir)
            return p
        }
    }

    /// Chromium stores the synced account photo as "<Product> Profile Picture.png"
    /// inside the profile directory.
    static func avatarFile(in profileDir: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: profileDir.path)
        else { return nil }
        return files.first { $0.hasSuffix("Profile Picture.png") }
            .map { profileDir.appendingPathComponent($0) }
    }

    private static func firefoxProfiles(base: URL, bundleId: String) -> [BrowserProfile] {
        let ini = base.appendingPathComponent("profiles.ini")
        guard let text = try? String(contentsOf: ini, encoding: .utf8) else { return [] }
        return parseProfilesINI(text, bundleId: bundleId)
    }
}
