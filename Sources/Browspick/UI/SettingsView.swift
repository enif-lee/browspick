import BrowspickCore
import SwiftUI

enum SettingsTab: String, Hashable {
    case general, browsers, rules, history

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .rules: "Rules"
        case .history: "History"
        }
    }
}

final class SettingsViewModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $vm.tab) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsTab.general)
                Label("Browsers", systemImage: "globe")
                    .tag(SettingsTab.browsers)
                Label("Rules", systemImage: "arrow.triangle.branch")
                    .tag(SettingsTab.rules)
                Label("History", systemImage: "clock")
                    .tag(SettingsTab.history)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch vm.tab {
                case .general: GeneralView()
                case .browsers: BrowsersView()
                case .rules: RulesView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(vm.tab.title)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.keyWindow?.firstResponder?
                        .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                } label: {
                    Image(systemName: "sidebar.leading")
                }
            }
        }
        .frame(minWidth: 1020, minHeight: 540)
    }
}
