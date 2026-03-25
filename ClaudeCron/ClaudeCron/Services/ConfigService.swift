import Foundation

final class ConfigService {
    static let shared = ConfigService()

    private let fileName = ".ccron/settings.json"

    func settingsFilePath(for folder: String) -> String {
        (folder as NSString).appendingPathComponent(fileName)
    }

    /// Read a .ccron/settings.json from a folder. Returns empty SettingsFile if not found or corrupt.
    func read(folder: String) -> SettingsFile {
        let path = settingsFilePath(for: folder)
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return SettingsFile()
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(SettingsFile.self, from: data)) ?? SettingsFile()
    }

    /// Write a SettingsFile to a folder's .ccron/settings.json. Creates .ccron/ directory if needed.
    func write(_ file: SettingsFile, to folder: String) throws {
        let dirPath = (folder as NSString).appendingPathComponent(".ccron")
        try FileManager.default.createDirectory(
            atPath: dirPath, withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let path = settingsFilePath(for: folder)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
