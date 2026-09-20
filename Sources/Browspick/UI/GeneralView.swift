import AppKit
import BrowspickCore
import ServiceManagement
import SwiftUI

struct GeneralView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var perm = OnboardingModel()

    private var isDefaultBrowser: Bool {
        guard let url = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: handler) else { return false }
        return bundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    var body: some View {
        Form {
            Section("Default Browser") {
                HStack {
                    Image(systemName: isDefaultBrowser ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isDefaultBrowser ? .green : .orange)
                    Text(isDefaultBrowser
                         ? "Browspick is the default browser"
                         : "Browspick is not the default browser")
                    Spacer()
                    if !isDefaultBrowser {
                        Button("Set as Default…") {
                            (NSApp.delegate as? AppDelegate)?.setAsDefaultBrowser()
                        }
                    }
                }
            }

            Section {
                ForEach(perm.checkedBrowsers, id: \.browser.id) { item in
                    LabeledContent(item.browser.name) {
                        if item.denied {
                            Label("Blocked", systemImage: "lock.trianglebadge.exclamationmark.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        } else {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
                if !perm.deniedBrowsers.isEmpty {
                    HStack(spacing: 8) {
                        Button("Request Access") {
                            for b in perm.deniedBrowsers {
                                _ = ProfileCatalog.profiles(for: b.bundleId)
                            }
                            perm.refresh()
                        }
                        .controlSize(.small)
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                HStack {
                    Text("Permissions")
                    Spacer()
                    HelpButton {
                        Text("Profile lists and browsing history live in each browser's "
                             + "Application Support data. macOS protects it — grant access "
                             + "under Privacy & Security → Files and Folders "
                             + "(or Full Disk Access).")
                            .frame(width: 280)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Launch at login", isOn: binding(\.launchAtLogin))
                    .onChange(of: config.launchAtLogin) { LoginItem.apply() }
                Toggle("Strip tracking parameters (utm_*, fbclid, gclid…)", isOn: binding(\.stripTrackingParams))
                Toggle("Show browser profiles in picker", isOn: binding(\.showProfilesInPicker))
                Toggle("Show private/incognito in picker", isOn: binding(\.showPrivateInPicker))
                Toggle("Suggest rules from browsing history", isOn: binding(\.useBrowsingHistory))
                Stepper("Suggest a rule after \(config.suggestionThreshold) repeated picks",
                        value: binding(\.suggestionThreshold), in: 2 ... 10)
                Stepper("History suggestion at \(config.historyMinVisits)+ visits",
                        value: binding(\.historyMinVisits), in: 3 ... 50)
            }

            if !config.dismissedSuggestions.isEmpty {
                Section("Dismissed Suggestions") {
                    ForEach(config.dismissedSuggestions, id: \.self) { key in
                        HStack {
                            Text(key.replacingOccurrences(of: "|", with: "  →  "))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button("Restore") {
                                state.update { $0.dismissedSuggestions.removeAll { $0 == key } }
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("Open Config Folder") {
                        NSWorkspace.shared.open(ConfigStore.supportDir)
                    }
                    Spacer()
                    Button("Quit Browspick") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { perm.refresh() }
    }

    private var config: Config { state.config }
    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { state.config[keyPath: keyPath] },
                set: { newValue in state.update { $0[keyPath: keyPath] = newValue } })
    }
}

/// "?" button that reveals explanatory text in a popover.
final class HelpModel: ObservableObject {
    @Published var show = false
}

struct HelpButton<Content: View>: View {
    @StateObject private var model = HelpModel()
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Button { model.show = true } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $model.show, arrowEdge: .trailing) {
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }
}
