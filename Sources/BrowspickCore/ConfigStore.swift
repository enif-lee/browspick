import Foundation

@MainActor
public final class ConfigStore {
    public static let shared = ConfigStore()

    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Browspick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public private(set) var config: Config
    private let fileURL: URL
    /// Called on the main queue after config changes (set by the app layer).
    public var onChange: (() -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.supportDir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
    }

    @discardableResult
    public func update(_ mutate: (inout Config) -> Void) -> Config {
        mutate(&config)
        save()
        onChange?()
        return config
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
