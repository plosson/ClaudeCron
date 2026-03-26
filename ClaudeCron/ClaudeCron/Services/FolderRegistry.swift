import Foundation

@Observable
@MainActor
final class FolderRegistry {
    private let defaults: UserDefaults
    private let key = "registeredFolders"

    private(set) var folders: [String] = []

    /// All folders including the implicit global (~) folder
    var allFolders: [String] {
        let home = NSHomeDirectory()
        if folders.contains(home) {
            return folders
        }
        return [home] + folders
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.folders = defaults.stringArray(forKey: key) ?? []
    }

    func add(_ folder: String) {
        guard !folders.contains(folder) else { return }
        folders.append(folder)
        save()
    }

    func remove(_ folder: String) {
        folders.removeAll { $0 == folder }
        save()
    }

    private func save() {
        defaults.set(folders, forKey: key)
    }
}
