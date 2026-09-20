import AppKit
import BrowspickCore

/// Central dispatch: incoming URL → clean → scheme API → rules → picker → launch + history.
@MainActor
final class Router {
    private var picker: PickerPanel?
    private var lastHandled: (url: String, time: Date)?

    var isPickerVisible: Bool { picker?.isVisible == true }

    func handle(url: URL, source: SourceApp?) {
        // Guard against double-delivery of the same link click.
        if let last = lastHandled,
           last.url == url.absoluteString,
           Date().timeIntervalSince(last.time) < 0.5 { return }
        lastHandled = (url.absoluteString, .now)

        if url.scheme?.lowercased() == SchemeAPI.scheme {
            handleSchemeURL(url, source: source)
            return
        }
        route(url: url, source: source)
    }

    private func handleSchemeURL(_ url: URL, source: SourceApp?) {
        // browspick:dump — write a profile-store debug dump from the app's TCC context.
        if (url.host ?? url.path).lowercased() == "dump" {
            try? ProfileCatalog.debugDump().write(
                to: ConfigStore.supportDir.appendingPathComponent("profiles-dump.txt"),
                atomically: true, encoding: .utf8)
            return
        }
        guard let request = SchemeAPI.parse(url) else { return }
        if let target = request.target {
            launch(url: request.url, target: target,
                   via: request.manualPick ? .manual : .rule, source: source)
        } else if request.forcePrompt {
            showPicker(url: request.url, source: source)
        } else {
            route(url: request.url, source: source)
        }
    }

    private func route(url: URL, source: SourceApp?) {
        var working = url
        let config = ConfigStore.shared.config
        if config.stripTrackingParams {
            working = URLCleaner.clean(url)
        }
        let engine = RuleEngine(rules: config.rules)
        guard let rule = engine.match(url: working, sourceBundleId: source?.bundleId) else {
            showPicker(url: working, source: source)
            return
        }
        let finalURL = rule.rewrite?.apply(to: working) ?? working
        switch rule.target {
        case .prompt:
            showPicker(url: finalURL, source: source)
        default:
            launch(url: finalURL, target: rule.target, via: .rule, source: source, originalURL: working)
        }
    }

    // MARK: - Picker

    func pickerEntries() -> [PickerEntry] {
        Self.pickerEntries(config: ConfigStore.shared.config)
    }

    /// Picker entries for a config — static so suggestion cards can offer the
    /// same target list without a Router instance.
    static func pickerEntries(config: Config) -> [PickerEntry] {
        let hidden = Set(config.hiddenPickerTargets)
        func add(_ target: Target, _ title: String, _ icon: NSImage?, to entries: inout [PickerEntry]) {
            if !hidden.contains(target.key) {
                entries.append(PickerEntry(target: target, title: title, icon: icon))
            }
        }
        var entries: [PickerEntry] = []
        for browser in BrowserCatalog.detect() where !config.hiddenBundleIds.contains(browser.bundleId) {
            let icon = BrowserCatalog.icon(for: browser.bundleId)
            add(.browser(bundleId: browser.bundleId), browser.name, icon, to: &entries)
            if config.showProfilesInPicker {
                // Include "Default" too — a bare launch opens Chromium's *last used*
                // profile, so the explicit profile entry is the deterministic choice.
                for profile in ProfileCatalog.profiles(for: browser.bundleId) {
                    // Chromium's Default profile carries a localized name
                    // ("내 Chrome" in ko) — annotate it so it's recognizable.
                    let name = profile.profileArg == "Default"
                        ? "\(profile.name) (Default)"
                        : profile.name
                    let entryIcon = profile.pictureURL
                        .flatMap { NSImage(contentsOf: $0) } ?? icon
                    var entry = PickerEntry(
                        target: .browser(bundleId: browser.bundleId, profile: profile.profileArg),
                        title: "\(browser.name) — \(name)", icon: entryIcon)
                    entry.isAvatar = profile.pictureURL != nil
                    if !hidden.contains(entry.target.key) {
                        entries.append(entry)
                    }
                }
            }
            if config.showPrivateInPicker,
               Launcher.privateArgs[browser.bundleId] != nil || browser.bundleId == "com.apple.Safari" {
                add(.browser(bundleId: browser.bundleId, isPrivate: true),
                    "\(browser.name) (Private)", icon, to: &entries)
            }
        }
        return entries
    }

    private func showPicker(url: URL, source: SourceApp?) {
        var entries = pickerEntries()
        guard !entries.isEmpty else {
            NSWorkspace.shared.open(url)
            return
        }
        // Pre-select the target last picked for this host/path pattern.
        var initialIndex = 0
        if let key = HistoryStore.shared.suggestedTargetKey(for: url),
           let idx = entries.firstIndex(where: { $0.target.key == key }) {
            entries[idx].isSuggested = true
            initialIndex = idx
        }
        MainActor.assumeIsolated { [self] in
            picker?.close()
            let panel = PickerPanel(
                url: url,
                entries: entries,
                initialIndex: initialIndex,
                onPick: { [weak self] entry, modifiers in
                    self?.pickerDidPick(entry: entry, url: url, source: source, modifiers: modifiers)
                },
                onCancel: { [weak self] in
                    self?.pickerClosed()
                }
            )
            picker = panel
            NSApp.setActivationPolicy(.regular)
            panel.showCentered()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func pickerDidPick(entry: PickerEntry, url: URL, source: SourceApp?, modifiers: NSEvent.ModifierFlags) {
        // ⌘-pick: also save a rule for this host
        if modifiers.contains(.command), let host = url.host {
            let pattern = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            ConfigStore.shared.update { config in
                var rule = Rule()
                rule.name = pattern
                rule.hostPatterns = [pattern]
                rule.target = entry.target
                config.rules.insert(rule, at: 0)
            }
        }
        launch(url: url, target: entry.target, via: .manual, source: source,
               background: modifiers.contains(.control))
        pickerClosed()
    }

    private func pickerClosed() {
        let panel = picker
        picker = nil
        panel?.close()
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Launch + history

    private func launch(url: URL, target: Target, via: PickRecord.Via, source: SourceApp?,
                        background: Bool = false, originalURL: URL? = nil) {
        let config = ConfigStore.shared.config
        Launcher.launch(url: url, target: target, background: background,
                        fallbackBundleId: config.fallbackBundleId)
        HistoryStore.shared.record(PickRecord(
            url: (originalURL ?? url).absoluteString,
            host: (originalURL ?? url).host ?? "",
            sourceBundleId: source?.bundleId,
            sourceName: source?.name,
            targetKey: target.key,
            via: via
        ))
    }
}
