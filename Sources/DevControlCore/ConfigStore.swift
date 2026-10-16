import Foundation

/// Loads and saves `AppConfig` as JSON inside a configurable directory
/// (Application Support in production, temp dirs in tests).
public struct ConfigStore {
    public let fileURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("config.json")
    }

    /// Default location: ~/Library/Application Support/DevMissionControl/
    public static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DevMissionControl", isDirectory: true)
    }

    public func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: fileURL.path)
    }

    /// Returns nil when no config file exists yet.
    public func load() throws -> AppConfig? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppConfig.self, from: Data(contentsOf: fileURL))
    }
}
