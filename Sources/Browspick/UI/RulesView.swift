import BrowspickCore
import SwiftUI

final class RulesViewModel: ObservableObject {
    @Published var selectedID: UUID?
    @Published var testURL = ""
}

struct RulesView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm = RulesViewModel()

    var body: some View {
        if state.config.rules.isEmpty {
            emptyState
        } else {
            HSplitView {
                ruleList
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rules", systemImage: "arrow.triangle.branch")
        } description: {
            Text("Rules route matching links straight to a browser,\nprofile, or native app — no picker prompt.")
                .multilineTextAlignment(.center)
        } actions: {
            HStack(spacing: 12) {
                Button("New Rule") { addRule() }
                    .buttonStyle(.borderedProminent)
                Menu("Add Preset") {
                    ForEach(NativeAppCatalog.presets) { preset in
                        Button(preset.name) { addPreset(preset) }
                    }
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rule list

    private var ruleList: some View {
        VStack(spacing: 0) {
            List(selection: $vm.selectedID) {
                ForEach(state.config.rules) { rule in
                    ruleRow(rule)
                        .tag(rule.id)
                        .contextMenu {
                            Button("Move Up") { moveSelection(by: -1) }
                            Button("Move Down") { moveSelection(by: 1) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteSelection() }
                        }
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { addRule() } label: { Image(systemName: "plus") }
                    .help("New rule")
                Menu {
                    ForEach(NativeAppCatalog.presets) { preset in
                        Button(preset.name) { addPreset(preset) }
                    }
                } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .menuStyle(.borderlessButton)
                    .help("Add native-app preset (Zoom, Slack, …)")
                Spacer()
                Button { moveSelection(by: -1) } label: { Image(systemName: "chevron.up") }
                    .help("Higher priority")
                    .disabled(vm.selectedID == nil)
                Button { moveSelection(by: 1) } label: { Image(systemName: "chevron.down") }
                    .help("Lower priority")
                    .disabled(vm.selectedID == nil)
                Divider().frame(height: 14)
                Button { deleteSelection() } label: { Image(systemName: "minus") }
                    .help("Delete rule")
                    .disabled(vm.selectedID == nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .buttonStyle(.borderless)
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 8) {
            targetIcon(rule.target)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name.isEmpty ? (rule.hostPatterns.first ?? "Untitled rule") : rule.name)
                    .lineLimit(1)
                Text(subtitle(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: enabledBinding(rule.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.vertical, 2)
        .opacity(rule.enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func targetIcon(_ target: Target) -> some View {
        switch target {
        case let .browser(b, _, priv, _):
            if let icon = BrowserCatalog.icon(for: b, size: 20) {
                Image(nsImage: icon)
                    .overlay(alignment: .bottomTrailing) {
                        if priv {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(.secondary, in: Circle())
                        }
                    }
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        case let .app(b):
            if let icon = BrowserCatalog.icon(for: b, size: 20) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "app").foregroundStyle(.secondary)
            }
        case .prompt:
            Image(systemName: "hand.point.up.left").foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ rule: Rule) -> String {
        let pattern = rule.hostPatterns.first ?? rule.urlRegex ?? "any URL"
        return "\(pattern) → \(targetLabel(rule.target))"
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if let id = vm.selectedID, let rule = state.config.rules.first(where: { $0.id == id }) {
            ruleEditor(rule)
        } else {
            ContentUnavailableView("Select a Rule",
                                   systemImage: "sidebar.left",
                                   description: Text("Pick a rule on the left, or create a new one."))
        }
    }

    private func ruleEditor(_ rule: Rule) -> some View {
        Form {
            Section {
                field("Name", prompt: "Optional",
                      text: ruleBinding(rule.id, \.name), mono: false)
                field("Host / URL patterns",
                      prompt: "github.com, *.google.com, google.com/maps/*",
                      text: hostPatternsBinding(rule.id), axis: .vertical)
            } header: {
                Text("Match")
            } footer: {
                Text("Comma-separated host globs — bare domains also match subdomains. "
                     + "A pattern containing / matches host + path.")
            }

            Section {
                field("URL regex",
                      prompt: #"^https://meet\.google\.com/.*"#,
                      text: optionalBinding(rule.id, \.urlRegex))
                if let regex = rule.urlRegex, !regex.isEmpty,
                   (try? NSRegularExpression(pattern: regex)) == nil {
                    Label("Invalid regular expression", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                field("Only when opened from apps",
                      prompt: "com.tinyspeck.slackmacgap, …",
                      text: sourceAppsBinding(rule.id))
            } footer: {
                Text("Regex matches the full URL. “Only from apps” restricts the rule "
                     + "to links clicked in those bundle IDs (empty = any source).")
            }

            Section {
                Picker("Open in", selection: targetKindBinding(rule.id)) {
                    Text("Browser").tag("browser")
                    Text("Native app").tag("app")
                    Text("Ask").tag("prompt")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                targetEditor(rule)
            } header: {
                Text("Target")
            }

            Section {
                field("Regex", prompt: "Leave empty to skip",
                      text: rewriteBinding(rule.id, \.regex))
                field("Template", prompt: "$1, $2… capture groups",
                      text: rewriteBinding(rule.id, \.template))
            } header: {
                Text("Rewrite URL")
            } footer: {
                Text("Applied after the rule matches, before the URL is opened — "
                     + "e.g. rewrite https to a custom scheme like zoommtg:.")
            }

            Section {
                field("Test URL", prompt: "https://…", text: $vm.testURL)
                Text(matchResult(for: vm.testURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Test")
            }
        }
        .formStyle(.grouped)
    }

    /// Label-above-field row: keeps labels on one line and gives inputs full width.
    private func field(_ label: String, prompt: String, text: Binding<String>,
                       mono: Bool = true, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text(prompt), axis: axis)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .lineLimit(axis == .vertical ? 2 ... 4 : 1 ... 1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func targetEditor(_ rule: Rule) -> some View {
        switch rule.target {
        case .browser:
            Picker("Browser", selection: targetBundleBinding(rule.id)) {
                ForEach(state.browsers) { b in
                    Label {
                        Text(b.name)
                    } icon: {
                        if let icon = BrowserCatalog.icon(for: b.bundleId, size: 16) {
                            Image(nsImage: icon)
                        }
                    }
                    .tag(b.bundleId)
                }
            }
            if case let .browser(bundleId, _, _, _) = rule.target {
                let profiles = ProfileCatalog.profiles(for: bundleId)
                if !profiles.isEmpty {
                    Picker("Profile", selection: profileBinding(rule.id)) {
                        Text("Default").tag(nil as String?)
                        ForEach(profiles) { p in
                            Text(p.name).tag(p.profileArg as String?)
                        }
                        // A rule may point at a profile deleted since it was
                        // created — show it rather than silently displaying
                        // "Default".
                        if case let .browser(_, current, _, _) = rule.target,
                           let current,
                           !profiles.contains(where: { $0.profileArg == current }) {
                            Text("\(current) (missing)").tag(current as String?)
                        }
                    }
                }
                Toggle("Private / incognito window", isOn: browserFlagBinding(rule.id, isPrivate: true))
                Toggle("Always open a new window", isOn: browserFlagBinding(rule.id, isPrivate: false))
            }
        case .app:
            Picker("App", selection: appBundleBinding(rule.id)) {
                ForEach(NativeAppCatalog.presets) { p in
                    Text("\(p.name) (\(p.appBundleId))").tag(p.appBundleId)
                }
            }
            field("Bundle ID", prompt: "us.zoom.xos", text: appBundleBinding(rule.id))
            Text("The rewritten URL (or the original) is handed to this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .prompt:
            Text("The picker is shown when this rule matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func matchResult(for input: String) -> String {
        guard !input.isEmpty, let url = URL(string: input) else { return "Enter a URL to test the whole rule chain" }
        var u = url
        if state.config.stripTrackingParams { u = URLCleaner.clean(u) }
        let engine = RuleEngine(rules: state.config.rules)
        if let rule = engine.match(url: u, sourceBundleId: nil) {
            let final = rule.rewrite?.apply(to: u) ?? u
            return "→ \(rule.name.isEmpty ? "Rule" : rule.name) → \(targetLabel(rule.target))\n\(final.absoluteString)"
        }
        return "→ No rule matches — picker will be shown"
    }

    private func targetLabel(_ target: Target) -> String {
        switch target {
        case let .browser(b, p, priv, nw):
            var s = BrowserCatalog.name(for: b)
            if let p { s += " — \(p)" }
            if priv { s += " (Private)" }
            if nw { s += " [new window]" }
            return s
        case let .app(b): return "App: \(BrowserCatalog.name(for: b))"
        case .prompt: return "Ask every time"
        }
    }

    private func addRule() {
        var rule = Rule()
        rule.name = "New rule"
        state.update { $0.rules.append(rule) }
        vm.selectedID = rule.id
    }

    private func addPreset(_ preset: NativeAppPreset) {
        let rules = preset.rules
        state.update { $0.rules.append(contentsOf: rules) }
        vm.selectedID = rules.first?.id
    }

    private func moveSelection(by delta: Int) {
        guard let id = vm.selectedID,
              let idx = state.config.rules.firstIndex(where: { $0.id == id }) else { return }
        let to = idx + delta
        guard state.config.rules.indices.contains(to) else { return }
        state.update { $0.rules.swapAt(idx, to) }
    }

    private func deleteSelection() {
        guard let id = vm.selectedID else { return }
        state.update { $0.rules.removeAll { $0.id == id } }
        vm.selectedID = nil
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { state.config.rules.first { $0.id == id }?.enabled ?? false },
                set: { v in state.update { c in c.rules.firstIndex(where: { $0.id == id }).map { c.rules[$0].enabled = v } } })
    }

    private func ruleBinding(_ id: UUID, _ keyPath: WritableKeyPath<Rule, String>) -> Binding<String> {
        Binding(get: { state.config.rules.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { v in updateRule(id) { $0[keyPath: keyPath] = v } })
    }

    private func optionalBinding(_ id: UUID, _ keyPath: WritableKeyPath<Rule, String?>) -> Binding<String> {
        Binding(get: { state.config.rules.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { v in updateRule(id) { $0[keyPath: keyPath] = v.isEmpty ? nil : v } })
    }

    private func hostPatternsBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { state.config.rules.first { $0.id == id }?.hostPatterns.joined(separator: ", ") ?? "" },
            set: { v in
                updateRule(id) {
                    $0.hostPatterns = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            }
        )
    }

    private func sourceAppsBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { state.config.rules.first { $0.id == id }?.sourceBundleIds.joined(separator: ", ") ?? "" },
            set: { v in
                updateRule(id) {
                    $0.sourceBundleIds = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            }
        )
    }

    private func rewriteBinding(_ id: UUID, _ keyPath: WritableKeyPath<URLRewrite, String>) -> Binding<String> {
        Binding(
            get: { state.config.rules.first { $0.id == id }?.rewrite?[keyPath: keyPath] ?? "" },
            set: { v in
                updateRule(id) { rule in
                    if rule.rewrite == nil { rule.rewrite = URLRewrite(regex: "", template: "") }
                    rule.rewrite?[keyPath: keyPath] = v
                    if rule.rewrite?.regex.isEmpty == true, rule.rewrite?.template.isEmpty == true {
                        rule.rewrite = nil
                    }
                }
            }
        )
    }

    private func targetKindBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                switch state.config.rules.first(where: { $0.id == id })?.target {
                case .browser: "browser"
                case .app: "app"
                default: "prompt"
                }
            },
            set: { kind in
                updateRule(id) { rule in
                    switch kind {
                    case "browser":
                        if case .browser = rule.target { break }
                        rule.target = .browser(bundleId: state.browsers.first?.bundleId ?? "com.apple.Safari")
                    case "app":
                        if case .app = rule.target { break }
                        rule.target = .app(bundleId: NativeAppCatalog.presets.first?.appBundleId ?? "")
                    default:
                        rule.target = .prompt
                    }
                }
            }
        )
    }

    private func targetBundleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard case let .browser(b, _, _, _) = state.config.rules.first(where: { $0.id == id })?.target else { return "" }
                return b
            },
            set: { v in updateRule(id) { if case .browser = $0.target { $0.target = .browser(bundleId: v) } } }
        )
    }

    private func appBundleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard case let .app(b) = state.config.rules.first(where: { $0.id == id })?.target else { return "" }
                return b
            },
            set: { v in updateRule(id) { if case .app = $0.target { $0.target = .app(bundleId: v) } } }
        )
    }

    private func profileBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: {
                guard case let .browser(_, p, _, _) = state.config.rules.first(where: { $0.id == id })?.target else { return nil }
                return p
            },
            set: { v in
                updateRule(id) {
                    if case let .browser(b, _, priv, nw) = $0.target {
                        $0.target = .browser(bundleId: b, profile: v, isPrivate: priv, newWindow: nw)
                    }
                }
            }
        )
    }

    private func browserFlagBinding(_ id: UUID, isPrivate: Bool) -> Binding<Bool> {
        Binding(
            get: {
                guard case let .browser(_, _, priv, nw) = state.config.rules.first(where: { $0.id == id })?.target else { return false }
                return isPrivate ? priv : nw
            },
            set: { v in
                updateRule(id) {
                    if case let .browser(b, p, priv, nw) = $0.target {
                        $0.target = .browser(bundleId: b, profile: p,
                                             isPrivate: isPrivate ? v : priv,
                                             newWindow: isPrivate ? nw : v)
                    }
                }
            }
        )
    }

    private func updateRule(_ id: UUID, _ mutate: (inout Rule) -> Void) {
        state.update { config in
            guard let idx = config.rules.firstIndex(where: { $0.id == id }) else { return }
            mutate(&config.rules[idx])
        }
    }
}
