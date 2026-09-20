import BrowspickCore
import Foundation
import SQLite3

// Plain assertion harness — CLT has neither XCTest nor the swift-testing macros plugin.

var failures = 0
var checks = 0

@MainActor func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    checks += 1
    if !cond {
        failures += 1
        print("FAIL  \(name)  \(detail)")
    }
}

@MainActor func eq<T: Equatable>(_ a: T, _ b: T, _ name: String) {
    check(a == b, name, "\(a) != \(b)")
}

// MARK: - PatternMatcher

do {
    let url = URL(string: "https://github.com/x")!
    check(PatternMatcher.hostMatches(pattern: "github.com", host: "github.com", url: url), "host exact")
    check(PatternMatcher.hostMatches(pattern: "github.com", host: "api.github.com", url: url), "host subdomain")
    check(!PatternMatcher.hostMatches(pattern: "github.com", host: "notgithub.com", url: url), "host no suffix-abuse")
    check(!PatternMatcher.hostMatches(pattern: "github.com", host: "github.com.evil.com", url: url), "host no evil suffix")
}

do {
    let url = URL(string: "https://gist.github.com/x")!
    check(PatternMatcher.hostMatches(pattern: "*.github.com", host: "gist.github.com", url: url), "wildcard subdomain")
    check(PatternMatcher.hostMatches(pattern: "*google*", host: "mail.google.com", url: url), "wildcard contains")
    check(!PatternMatcher.hostMatches(pattern: "*.github.com", host: "github.com", url: url), "wildcard needs sub")
}

do {
    let url = URL(string: "https://google.com/maps/place/x")!
    check(PatternMatcher.hostMatches(pattern: "google.com/maps/*", host: "google.com", url: url), "url glob")
    check(!PatternMatcher.hostMatches(pattern: "google.com/mail/*", host: "google.com", url: url), "url glob miss")
}

// MARK: - URLRewrite

do {
    let rw = URLRewrite(
        regex: #"^https?://[^/]*zoom\.us/(?:j|my)/(\d+)[^#]*?(?:[?&]pwd=([^&#]+))?.*$"#,
        template: "zoommtg://zoom.us/join?confno=$1&pwd=$2"
    )
    eq(rw.apply(to: URL(string: "https://zoom.us/j/123456789?pwd=abc")!)?.absoluteString,
       "zoommtg://zoom.us/join?confno=123456789&pwd=abc", "zoom rewrite")
    eq(rw.apply(to: URL(string: "https://us02web.zoom.us/j/999")!)?.absoluteString,
       "zoommtg://zoom.us/join?confno=999&pwd=", "zoom rewrite no pwd")
    check(rw.apply(to: URL(string: "https://example.com/j/123")!) == nil, "zoom no match")
}

do {
    let rw = URLRewrite(
        regex: #"^https?://open\.spotify\.com/(?:intl-[a-z-]+/)?(track|album|playlist|artist|episode|show)/([A-Za-z0-9]+)"#,
        template: "spotify:$1:$2"
    )
    eq(rw.apply(to: URL(string: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")!)?.absoluteString,
       "spotify:track:4uLU6hMCjMI75M1A2tKUQC", "spotify rewrite")
    eq(rw.apply(to: URL(string: "https://open.spotify.com/intl-ko/album/xyz")!)?.absoluteString,
       "spotify:album:xyz", "spotify intl prefix")
}

// MARK: - RuleEngine

do {
    var r1 = Rule(); r1.hostPatterns = ["github.com"]; r1.target = .browser(bundleId: "org.mozilla.firefox")
    var r2 = Rule(); r2.hostPatterns = ["github.com"]; r2.sourceBundleIds = ["com.tinyspeck.slackmacgap"]
    r2.target = .browser(bundleId: "com.google.Chrome")
    let engine = RuleEngine(rules: [r2, r1])
    let url = URL(string: "https://github.com/a")!
    eq(engine.match(url: url, sourceBundleId: "com.tinyspeck.slackmacgap")?.target,
       .browser(bundleId: "com.google.Chrome"), "source-gated rule wins")
    eq(engine.match(url: url, sourceBundleId: "com.apple.mail")?.target,
       .browser(bundleId: "org.mozilla.firefox"), "fallback rule for other source")
    eq(engine.match(url: url, sourceBundleId: nil)?.target,
       .browser(bundleId: "org.mozilla.firefox"), "nil source skips gated rule")
}

do {
    var off = Rule(); off.enabled = false; off.hostPatterns = ["x.com"]
    let empty = Rule()
    let engine = RuleEngine(rules: [off, empty])
    check(engine.match(url: URL(string: "https://x.com")!, sourceBundleId: nil) == nil, "disabled/empty skipped")
}

// MARK: - URLCleaner

do {
    let url = URL(string: "https://x.com/p?utm_source=twitter&keep=1&fbclid=zz")!
    let out = URLCleaner.clean(url)
    check(out.absoluteString.contains("keep=1"), "keeps normal param")
    check(!out.absoluteString.contains("utm_source"), "strips utm")
    check(!out.absoluteString.contains("fbclid"), "strips fbclid")
    eq(URLCleaner.clean(URL(string: "https://x.com/?gclid=1")!).absoluteString, "https://x.com/", "all-tracking drops query")
}

// MARK: - SuggestionEngine

do {
    let ff = Target.browser(bundleId: "org.mozilla.firefox")
    let ch = Target.browser(bundleId: "com.google.Chrome")
    func pick(_ host: String, _ target: Target, via: PickRecord.Via = .manual) -> PickRecord {
        PickRecord(url: "https://\(host)/", host: host, sourceBundleId: nil,
                   sourceName: nil, targetKey: target.key, via: via)
    }

    var s = SuggestionEngine.suggestions(
        records: [pick("github.com", ff), pick("github.com", ff)],
        rules: [], dismissed: [], threshold: 2)
    eq(s.count, 1, "two same picks → suggestion")
    eq(s.first?.pattern, "github.com", "suggestion pattern")

    s = SuggestionEngine.suggestions(
        records: [pick("www.github.com", ff), pick("github.com", ff)],
        rules: [], dismissed: [], threshold: 2)
    eq(s.count, 1, "www normalized")

    s = SuggestionEngine.suggestions(
        records: [pick("github.com", ff), pick("github.com", ch)],
        rules: [], dismissed: [], threshold: 2)
    check(s.isEmpty, "different browsers → no suggestion")

    s = SuggestionEngine.suggestions(
        records: [pick("github.com", ff), pick("github.com", ff)],
        rules: [], dismissed: ["github.com|\(ff.key)"], threshold: 2)
    check(s.isEmpty, "dismissed never resurfaces")

    var rule = Rule(); rule.hostPatterns = ["github.com"]; rule.target = ff
    s = SuggestionEngine.suggestions(
        records: [pick("github.com", ff), pick("github.com", ff)],
        rules: [rule], dismissed: [], threshold: 2)
    check(s.isEmpty, "covered by rule → suppressed")

    s = SuggestionEngine.suggestions(
        records: [pick("x.com", ff, via: .rule), pick("x.com", ff)],
        rules: [], dismissed: [], threshold: 2)
    check(s.isEmpty, "rule-routed picks don't count")
}

// MARK: - Target key round-trip

do {
    let t = Target.browser(bundleId: "com.google.Chrome", profile: "Profile 1", isPrivate: true, newWindow: false)
    eq(Target(key: t.key), t, "browser target key round-trip")
    eq(Target(key: Target.app(bundleId: "us.zoom.xos").key), .app(bundleId: "us.zoom.xos"), "app key round-trip")
    eq(Target(key: Target.prompt.key), .prompt, "prompt key round-trip")
    check(Target(key: "garbage") == nil, "garbage key rejected")
}

// MARK: - ProfileCatalog parsers

do {
    let json = """
    {"profile": {"info_cache": {
        "Default": {"name": "Personal"},
        "Profile 1": {"name": "Work"},
        "Profile 2": {},
        "Profile 3": {"name": "Profile 3", "user_name": "ed@corp.com"},
        "Profile 4": {"name": "Profile 4", "gaia_name": "Ed Kim"}
    }}}
    """.data(using: .utf8)!
    let profiles = ProfileCatalog.parseLocalState(json, bundleId: "com.google.Chrome")
    eq(profiles.count, 5, "local state count")
    check(profiles.contains { $0.profileArg == "Profile 1" && $0.name == "Work" }, "local state work profile")
    check(profiles.contains { $0.profileArg == "Profile 2" && $0.name == "Profile 2" }, "unnamed falls back to dir")
    check(profiles.contains { $0.profileArg == "Profile 3" && $0.name == "ed@corp.com" }, "generic name → user_name")
    check(profiles.contains { $0.profileArg == "Profile 4" && $0.name == "Ed Kim" }, "generic name → gaia_name")
}

do {
    let ini = """
    [Install4F96D1932A9F858E]
    Default=Profiles/abc.default-release

    [Profile0]
    Name=default-release
    IsRelative=1
    Path=Profiles/abc.default-release

    [Profile1]
    Name=work
    IsRelative=1
    Path=Profiles/def.work
    """
    let profiles = ProfileCatalog.parseProfilesINI(ini, bundleId: "org.mozilla.firefox")
    eq(profiles.map(\.profileArg), ["default-release", "work"], "profiles.ini parse")
}

// MARK: - Launcher args

do {
    eq(Launcher.browserArgs(bundleId: "com.google.Chrome", profile: "Work", isPrivate: true, newWindow: true),
       ["--profile-directory=Work", "--incognito", "--new-window"], "chrome args")
    eq(Launcher.browserArgs(bundleId: "org.mozilla.firefox", profile: "dev", isPrivate: true, newWindow: false),
       ["-P", "dev", "-private-window"], "firefox args")
    eq(Launcher.browserArgs(bundleId: "com.microsoft.edgemac", profile: nil, isPrivate: true, newWindow: false),
       ["--inprivate"], "edge inprivate")
    check(Launcher.browserArgs(bundleId: "com.apple.Safari", profile: nil, isPrivate: false, newWindow: false).isEmpty,
          "safari no args")
}

// MARK: - SchemeAPI

do {
    let r = SchemeAPI.parse(URL(string: "browspick:open?url=https%3A%2F%2Fx.com&prompt")!)
    eq(r?.url.absoluteString, "https://x.com", "scheme url")
    check(r?.forcePrompt == true, "scheme prompt flag")
    check(r?.target == nil, "scheme no target")

    let forced = SchemeAPI.parse(URL(string: "browspick:open?url=https%3A%2F%2Fx.com&app=org.mozilla.firefox&private")!)
    eq(forced?.target, .browser(bundleId: "org.mozilla.firefox", isPrivate: true), "scheme forced private")
    check(forced?.forcePrompt == false, "forced clears prompt")

    let priv = SchemeAPI.parse(URL(string: "browspick:open?url=https%3A%2F%2Fx.com&app=privateBrowser:org.mozilla.firefox")!)
    eq(priv?.target, .browser(bundleId: "org.mozilla.firefox", isPrivate: true), "privateBrowser prefix")

    check(SchemeAPI.parse(URL(string: "https://x.com")!) == nil, "non-scheme rejected")
    check(SchemeAPI.parse(URL(string: "browspick:open")!) == nil, "missing url rejected")
}

// MARK: - ProfileCatalog access status

do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let chromeDir = tmp.appendingPathComponent("Google/Chrome")
    try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)
    check(ProfileCatalog.accessStatus(for: "com.apple.Safari", supportDir: tmp) == .notApplicable,
          "safari has no profile store")
    check(ProfileCatalog.accessStatus(for: "com.google.Chrome", supportDir: tmp) == .granted,
          "missing Local State → granted")
    try Data("{}".utf8).write(to: chromeDir.appendingPathComponent("Local State"))
    check(ProfileCatalog.accessStatus(for: "com.google.Chrome", supportDir: tmp) == .granted,
          "readable Local State → granted")
    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - BrowserHistory

do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let chrome = tmp.appendingPathComponent("Google/Chrome")
    let profDir = chrome.appendingPathComponent("Profile 9")
    try FileManager.default.createDirectory(at: profDir, withIntermediateDirectories: true)
    try #"{"profile":{"info_cache":{"Profile 9":{"name":"Work"}}}}"#
        .write(to: chrome.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)

    // Build a minimal Chromium History db.
    var db: OpaquePointer?
    check(sqlite3_open(profDir.appendingPathComponent("History").path, &db) == SQLITE_OK, "create test db")
    sqlite3_exec(db, "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER, last_visit_time INTEGER)", nil, nil, nil)
    for (u, c) in [("https://github.com/a", 40), ("https://www.github.com/b", 10),
                   ("https://news.ycombinator.com", 3), ("chrome://settings", 9)] {
        sqlite3_exec(db, "INSERT INTO urls(url, visit_count, last_visit_time) VALUES('\(u)', \(c), 1)", nil, nil, nil)
    }
    sqlite3_close(db)

    let visits = BrowserHistory.allVisits(supportDir: tmp)
    if let v = visits.first {
        eq(v.targetKey, "b|com.google.Chrome|Profile 9|0|0", "history target key")
        eq(v.label, "Chrome — Work", "history label")
        eq(v.counts["github.com"], 50, "www. merged into host")
        eq(v.counts["news.ycombinator.com"], 3, "small count kept")
        check(v.counts["settings"] == nil, "chrome:// skipped")
    } else {
        check(false, "history read")
    }

    // History-derived suggestions: 50/50 dominant in Profile 9.
    let sug = SuggestionEngine.historySuggestions(visits: visits, rules: [], dismissed: [], minVisits: 5)
    eq(sug.first?.pattern, "github.com", "history suggestion pattern")
    eq(sug.first?.targetKey, "b|com.google.Chrome|Profile 9|0|0", "history suggestion target")
    eq(sug.first?.source, .history, "history suggestion source")
    check(!sug.contains { $0.pattern == "news.ycombinator.com" }, "below minVisits excluded")

    // Competing profile splits dominance below 50% → no suggestion.
    let edge = ProfileVisits(targetKey: "b|com.microsoft.edgemac|-|0|0", label: "Edge",
                             counts: ["github.com": 50])
    let sug2 = SuggestionEngine.historySuggestions(visits: visits + [edge], rules: [], dismissed: [], minVisits: 5)
    check(!sug2.contains { $0.pattern == "github.com" }, "split visits → no suggestion")

    // Firefox profiles.ini → directory resolution.
    let ff = tmp.appendingPathComponent("Firefox")
    try FileManager.default.createDirectory(at: ff, withIntermediateDirectories: true)
    let ini = """
        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release
        [Profile1]
        Name=work
        IsRelative=0
        Path=/tmp/ff-work-profile
        """
    let iniURL = ff.appendingPathComponent("profiles.ini")
    try ini.write(to: iniURL, atomically: true, encoding: .utf8)
    let dirs = BrowserHistory.firefoxProfileDirs(ini: iniURL, root: ff)
    eq(dirs.count, 2, "firefox dirs parsed")
    eq(dirs[0].url.path, ff.appendingPathComponent("Profiles/abc.default-release").path, "relative path")
    eq(dirs[1].url.path, "/tmp/ff-work-profile", "absolute path")

    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - NativeAppCatalog presets

do {
    let slack = NativeAppCatalog.presets.first { $0.name == "Slack" }!
    let slackRules = slack.rules
    eq(slackRules.count, 2, "slack preset emits 2 rules")
    let engine = RuleEngine(rules: slackRules)

    // Workspace permalink → slack://channel?id=…
    let perm = URL(string: "https://acme.slack.com/archives/C1234567890/p1700000000000000")!
    let permRule = engine.match(url: perm, sourceBundleId: nil)
    eq(permRule?.rewrite?.apply(to: perm)?.absoluteString,
       "slack://channel?id=C1234567890", "slack workspace permalink rewrite")

    // Client link → slack://channel?team=…&id=…
    let client = URL(string: "https://app.slack.com/client/T123/C456")!
    let clientRule = engine.match(url: client, sourceBundleId: nil)
    eq(clientRule?.rewrite?.apply(to: client)?.absoluteString,
       "slack://channel?team=T123&id=C456", "slack client link rewrite")

    // Non-matching slack.com URL still routes to Slack app with the original URL.
    let other = URL(string: "https://acme.slack.com/features")!
    let otherRule = engine.match(url: other, sourceBundleId: nil)
    check(otherRule != nil, "other slack.com links still match")
    check(otherRule?.rewrite?.apply(to: other) == nil, "non-permalink keeps original URL")

    let discord = NativeAppCatalog.presets.first { $0.name == "Discord" }!.rules
    let dEngine = RuleEngine(rules: discord)
    let invite = URL(string: "https://discord.gg/abc123")!
    eq(dEngine.match(url: invite, sourceBundleId: nil)?.rewrite?.apply(to: invite)?.absoluteString,
       "discord://discord.gg/abc123", "discord invite rewrite")

    let telegram = NativeAppCatalog.presets.first { $0.name == "Telegram" }!.rules
    let tEngine = RuleEngine(rules: telegram)
    let chan = URL(string: "https://t.me/mychannel/123")!
    eq(tEngine.match(url: chan, sourceBundleId: nil)?.rewrite?.apply(to: chan)?.absoluteString,
       "tg://resolve?domain=mychannel", "telegram channel rewrite")
    let invite2 = URL(string: "https://t.me/joinchat/AbCdEf")!
    eq(tEngine.match(url: invite2, sourceBundleId: nil)?.rewrite?.apply(to: invite2)?.absoluteString,
       "tg://join?invite=AbCdEf", "telegram joinchat rewrite")
}

// MARK: - HistoryStore suggested target

do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
    let store = HistoryStore(fileURL: tmp)
    let work = Target.browser(bundleId: "com.google.Chrome", profile: "Profile 1")
    let personal = Target.browser(bundleId: "com.google.Chrome", profile: "Default")

    func rec(_ url: String, _ target: Target, via: PickRecord.Via = .manual,
             at date: Date = .now) -> PickRecord {
        let u = URL(string: url)!
        return PickRecord(timestamp: date, url: url, host: u.host ?? "",
                          sourceBundleId: nil, sourceName: nil, targetKey: target.key, via: via)
    }

    // Host-only history applies to any path on that host.
    store.record(rec("https://github.com/", work))
    eq(store.suggestedTargetKey(for: URL(string: "https://github.com/other/page")!),
       work.key, "host match suggests last pick")

    // A longer shared path prefix beats a host-only record.
    store.record(rec("https://github.com/personal/dotfiles", personal,
                     at: .now.addingTimeInterval(60)))
    eq(store.suggestedTargetKey(for: URL(string: "https://github.com/personal/notes")!),
       personal.key, "shared path prefix wins over host-only")
    eq(store.suggestedTargetKey(for: URL(string: "https://github.com/work/repo")!),
       work.key, "different path → host-only pick")

    // Same prefix length → most recent wins.
    store.record(rec("https://news.ycombinator.com/item/1", work, at: .distantPast))
    store.record(rec("https://news.ycombinator.com/item/2", personal))
    eq(store.suggestedTargetKey(for: URL(string: "https://news.ycombinator.com/item/9")!),
       personal.key, "most recent wins on tie")

    // www normalization + rule-via records ignored + unknown host → nil.
    eq(store.suggestedTargetKey(for: URL(string: "https://www.github.com/x")!),
       work.key, "www normalized")
    store.record(rec("https://slack.com/x", work, via: .rule))
    check(store.suggestedTargetKey(for: URL(string: "https://slack.com/y")!) == nil,
          "rule-routed records ignored")
    check(store.suggestedTargetKey(for: URL(string: "https://never-seen.example")!) == nil,
          "unknown host → nil")
    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - Profile avatar + stale-dir filtering

do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let chrome = tmp.appendingPathComponent("Google/Chrome")
    try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
    // info_cache lists 3 profiles; only 2 directories exist → stale entry dropped.
    try #"{"profile":{"info_cache":{"Profile 1":{"name":"acme.example"},"Profile 2":{"name":"qa"},"Profile 9":{"name":"ghost"}}}}"#
        .write(to: chrome.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
    for d in ["Profile 1", "Profile 2"] {
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent(d),
                                                withIntermediateDirectories: true)
    }
    try Data("png".utf8).write(to: chrome.appendingPathComponent("Profile 1/Google Profile Picture.png"))

    let profiles = ProfileCatalog.profiles(for: "com.google.Chrome", supportDir: tmp)
    eq(profiles.count, 2, "stale profile dir filtered")
    check(!profiles.contains { $0.profileArg == "Profile 9" }, "missing dir excluded")
    eq(profiles.first { $0.profileArg == "Profile 1" }?.pictureURL?.lastPathComponent,
       "Google Profile Picture.png", "avatar detected")
    check(profiles.first { $0.profileArg == "Profile 2" }?.pictureURL == nil, "no avatar → nil")
    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - Config backward compatibility

do {
    // A config.json written by an older build (missing newer keys) must still decode.
    let json = #"{"rules":[],"suggestionThreshold":3,"hiddenBundleIds":["x"]}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(Config.self, from: json)
    eq(c.suggestionThreshold, 3, "old config keeps values")
    eq(c.hiddenBundleIds, ["x"], "old config arrays decode")
    check(c.hiddenPickerTargets.isEmpty, "hiddenPickerTargets defaults empty")
    check(c.launchAtLogin, "launchAtLogin defaults true")
    check(c.showProfilesInPicker, "showProfilesInPicker defaults true")
}

print("\n\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
