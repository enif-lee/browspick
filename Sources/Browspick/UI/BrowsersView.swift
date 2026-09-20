import BrowspickCore
import SwiftUI

struct BrowsersView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(state.browsers) { browser in
                    BrowserEntryView(browser: browser)
                }
            } header: {
                HStack {
                    Text("Picker Entries")
                    Spacer()
                    Button("Rescan") { state.browsers = BrowserCatalog.detect() }
                        .controlSize(.small)
                }
            } footer: {
                Text("Each browser profile registers as its own picker entry. "
                     + "Hidden entries stay usable in rules.")
            }

            Section("Fallback") {
                Picker("When a target can't be opened", selection: fallbackBinding) {
                    Text("System default").tag(nil as String?)
                    ForEach(state.browsers) { b in
                        Text(b.name).tag(b.bundleId as String?)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var fallbackBinding: Binding<String?> {
        Binding(get: { state.config.fallbackBundleId },
                set: { v in state.update { $0.fallbackBundleId = v } })
    }
}

/// One browser plus its registered picker entries (default, each profile, private).
private struct BrowserEntryView: View {
    @EnvironmentObject var state: AppState
    let browser: BrowserInfo

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                if ProfileCatalog.accessStatus(for: browser.bundleId) == .denied {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Profiles blocked by macOS privacy")
                                .font(.callout)
                            Text("Allow Browspick under Privacy & Security → Files and Folders")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                ForEach(entries, id: \.target.key) { entry in
                    HStack(spacing: 8) {
                        if let image = entry.image {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: entry.icon)
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.title)
                        if let detail = entry.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("In picker", isOn: shownBinding(entry.target))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.leading, 28)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                if let icon = BrowserCatalog.icon(for: browser.bundleId, size: 22) {
                    Image(nsImage: icon)
                }
                Text(browser.name)
                    .fontWeight(.medium)
                Text(browser.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("In picker", isOn: browserShownBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private struct Entry {
        let target: Target
        let title: String
        let detail: String?
        let icon: String
        var image: NSImage? = nil
    }

    private var entries: [Entry] {
        var list = [Entry(target: .browser(bundleId: browser.bundleId),
                          title: "Last used profile", detail: "no profile flag", icon: "macwindow")]
        for p in ProfileCatalog.profiles(for: browser.bundleId) {
            list.append(Entry(target: .browser(bundleId: browser.bundleId, profile: p.profileArg),
                              title: p.name, detail: p.profileArg, icon: "person.crop.circle",
                              image: p.pictureURL.flatMap { NSImage(contentsOf: $0) }))
        }
        if Launcher.privateArgs[browser.bundleId] != nil || browser.bundleId == "com.apple.Safari" {
            list.append(Entry(target: .browser(bundleId: browser.bundleId, isPrivate: true),
                              title: "Private / Incognito", detail: nil, icon: "eye.slash"))
        }
        return list
    }

    private var browserShownBinding: Binding<Bool> {
        Binding(
            get: { !state.config.hiddenBundleIds.contains(browser.bundleId) },
            set: { shown in
                state.update { config in
                    if shown {
                        config.hiddenBundleIds.removeAll { $0 == browser.bundleId }
                    } else if !config.hiddenBundleIds.contains(browser.bundleId) {
                        config.hiddenBundleIds.append(browser.bundleId)
                    }
                }
            }
        )
    }

    private func shownBinding(_ target: Target) -> Binding<Bool> {
        Binding(
            get: { !state.config.hiddenPickerTargets.contains(target.key) },
            set: { shown in
                state.update { config in
                    if shown {
                        config.hiddenPickerTargets.removeAll { $0 == target.key }
                    } else if !config.hiddenPickerTargets.contains(target.key) {
                        config.hiddenPickerTargets.append(target.key)
                    }
                }
            }
        )
    }
}
