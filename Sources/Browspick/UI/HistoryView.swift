import BrowspickCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            if !state.suggestions.isEmpty {
                Section("Suggested Rules") {
                    ForEach(state.suggestions) { suggestion in
                        SuggestionCard(suggestion: suggestion)
                    }
                }
            }

            Section("Recent Links") {
                ForEach(Array(state.records.reversed().enumerated()), id: \.offset) { _, record in
                    recordRow(record)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { state.refreshHistory() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Re-read browser history")
            }
            ToolbarItem {
                Button("Clear") { HistoryStore.shared.clear(); state.records = [] }
            }
        }
        .onAppear { state.refreshHistory() }
    }

    private func recordRow(_ r: PickRecord) -> some View {
        HStack(spacing: 8) {
            Text(r.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            if let source = r.sourceName {
                Text(source)
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Text(r.url)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(viaLabel(r.via))
                .font(.caption2)
                .foregroundStyle(r.via == .manual ? .orange : .green)
            Text(targetLabel(r.targetKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func viaLabel(_ via: PickRecord.Via) -> String {
        switch via {
        case .manual: "manual"
        case .rule: "rule"
        case .fallback: "fallback"
        }
    }

    private func targetLabel(_ key: String) -> String {
        guard let target = Target(key: key) else { return key }
        switch target {
        case let .browser(b, p, priv, _): return browserLabel(b, p, priv)
        case let .app(b): return BrowserCatalog.name(for: b)
        case .prompt: return "Prompt"
        }
    }
}

/// "Chrome — Work" style label, resolving the profile's display name
/// (account name / user-set name) rather than the directory arg.
func browserLabel(_ bundleId: String, _ profile: String?, _ isPrivate: Bool) -> String {
    var s = BrowserCatalog.name(for: bundleId)
    if let profile {
        let name = ProfileCatalog.profiles(for: bundleId)
            .first { $0.profileArg == profile }?.name ?? profile
        s += " — \(name)"
        if profile == "Default" { s += " (Default)" }
    }
    if isPrivate { s += " (Private)" }
    return s
}

/// A suggested rule card — pinned at the top of History.
/// Accept creates the rule; dismiss permanently suppresses this (pattern, target) pair.
final class SuggestionCardModel: ObservableObject {
    @Published var pattern: String
    @Published var targetKey: String
    init(pattern: String, targetKey: String) {
        self.pattern = pattern
        self.targetKey = targetKey
    }
}

struct SuggestionCard: View {
    @EnvironmentObject var state: AppState
    let suggestion: Suggestion
    @StateObject private var model: SuggestionCardModel

    init(suggestion: Suggestion) {
        self.suggestion = suggestion
        _model = StateObject(wrappedValue: SuggestionCardModel(
            pattern: suggestion.pattern, targetKey: suggestion.targetKey))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            TextField("Pattern", text: $model.pattern)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Picker("", selection: $model.targetKey) {
                ForEach(targetOptions, id: \.key) { option in
                    Text(option.title).tag(option.key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .fontWeight(.medium)
            if !evidenceLine.isEmpty {
                Text(evidenceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button("Accept") { accept() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Compact evidence: "×2 · Chrome — Work ×42 · Edge ×3"
    private var evidenceLine: String {
        var parts: [String] = []
        if suggestion.source == .picks {
            parts.append("×\(suggestion.evidenceCount)")
        }
        parts += suggestion.historyHits.prefix(3).map { "\($0.label) ×\($0.count)" }
        return parts.joined(separator: "  ·  ")
    }

    /// Same target list the picker offers, plus the suggestion's own target
    /// when it isn't a browser entry (e.g. a native-app suggestion).
    private var targetOptions: [(key: String, title: String)] {
        var options = Router.pickerEntries(config: state.config)
            .map { (key: $0.target.key, title: $0.title) }
        if !options.contains(where: { $0.key == suggestion.targetKey }),
           let target = Target(key: suggestion.targetKey) {
            options.insert((suggestion.targetKey, targetLabel(target)), at: 0)
        }
        return options
    }

    private func targetLabel(_ target: Target) -> String {
        switch target {
        case let .browser(b, p, priv, _): return browserLabel(b, p, priv)
        case let .app(b): return BrowserCatalog.name(for: b)
        case .prompt: return "Prompt"
        }
    }

    private func accept() {
        guard let target = Target(key: model.targetKey), !model.pattern.isEmpty else { return }
        state.update { config in
            var rule = Rule()
            rule.name = model.pattern
            rule.hostPatterns = [model.pattern]
            rule.target = target
            config.rules.insert(rule, at: 0)
        }
    }

    private func dismiss() {
        state.update { config in
            if !config.dismissedSuggestions.contains(suggestion.id) {
                config.dismissedSuggestions.append(suggestion.id)
            }
        }
    }
}
