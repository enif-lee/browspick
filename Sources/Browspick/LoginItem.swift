import BrowspickCore
import ServiceManagement

@MainActor
enum LoginItem {
    static func apply() {
        let service = SMAppService.mainApp
        do {
            if ConfigStore.shared.config.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Browspick: login item failed: \(error.localizedDescription)")
        }
    }
}
