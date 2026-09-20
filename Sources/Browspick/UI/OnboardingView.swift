import AppKit
import BrowspickCore
import Combine
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var isDefault = false
    /// Installed browsers that actually have a profile store on disk, with denied state.
    @Published var checkedBrowsers: [(browser: BrowserInfo, denied: Bool)] = []

    var deniedBrowsers: [BrowserInfo] {
        checkedBrowsers.filter(\.denied).map(\.browser)
    }

    func refresh() {
        if let url = URL(string: "https://example.com"),
           let handler = NSWorkspace.shared.urlForApplication(toOpen: url),
           let bundle = Bundle(url: handler) {
            isDefault = bundle.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        checkedBrowsers = BrowserCatalog.detect().compactMap { b in
            guard let store = ProfileCatalog.profileStoreURL(for: b.bundleId),
                  FileManager.default.fileExists(atPath: store.path) else { return nil }
            return (b, ProfileCatalog.accessStatus(for: b.bundleId) == .denied)
        }
    }

    var allComplete: Bool { isDefault && deniedBrowsers.isEmpty }
}

/// Shown on every launch/reopen until setup is complete:
/// default browser set + profile-file access granted (or no profile browsers installed).
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = OnboardingModel()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            steps
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 560)
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Browspick")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Browspick intercepts links and routes them to the right browser, "
                     + "profile, or app. Finish these steps to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepRow(
                done: model.isDefault,
                title: "Set as default browser",
                detail: "macOS delivers clicked links to Browspick only when it is the default browser."
            ) {
                Button("Set as Default…") {
                    (NSApp.delegate as? AppDelegate)?.setAsDefaultBrowser()
                }
                .controlSize(.small)
            }

            stepRow(
                done: model.deniedBrowsers.isEmpty,
                title: "Allow browser profile access",
                detail: model.deniedBrowsers.isEmpty
                    ? "Browspick can read browser profile lists (Chrome, Edge, Firefox…)."
                    : "macOS is blocking profile data for: "
                      + model.deniedBrowsers.map(\.name).joined(separator: ", ")
                      + ". Grant access under Privacy & Security → Files and Folders. "
                      + "If that doesn't take effect, add Browspick to Full Disk Access."
            ) {
                HStack(spacing: 8) {
                    if !model.deniedBrowsers.isEmpty {
                        Button("Request Access") {
                            for b in model.deniedBrowsers {
                                _ = ProfileCatalog.profiles(for: b.bundleId)
                            }
                        }
                        .controlSize(.small)
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                        }
                        .controlSize(.small)
                    }
                }
            }

            stepRow(
                done: state.config.launchAtLogin,
                title: "Launch at login",
                detail: "Keeps Browspick watching for links after a restart."
            ) {
                Toggle("", isOn: Binding(
                    get: { state.config.launchAtLogin },
                    set: { v in
                        state.update { $0.launchAtLogin = v }
                        LoginItem.apply()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private func stepRow<Actions: View>(
        done: Bool, title: String, detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            if model.allComplete {
                Label("All set — Browspick is ready.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("This window appears until every step is complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                (NSApp.delegate as? AppDelegate)?.showSettings()
            }
            Button("Done") {
                (NSApp.delegate as? AppDelegate)?.closeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.allComplete)
        }
    }
}
