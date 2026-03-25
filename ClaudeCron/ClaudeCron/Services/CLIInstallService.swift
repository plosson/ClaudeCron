import Foundation

enum CLIInstallService {
    static let cliName = "ccron"
    static let symlinkPath = "/usr/local/bin/\(cliName)"

    static var isInstalled: Bool {
        let fm = FileManager.default
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: symlinkPath),
              let execPath = Bundle.main.executablePath else { return false }
        return dest == execPath
    }

    static func install() throws {
        guard let execPath = Bundle.main.executablePath else {
            throw CLIInstallError.noExecutablePath
        }
        let fm = FileManager.default
        try? fm.removeItem(atPath: symlinkPath)
        try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: execPath)
    }

    static func uninstall() throws {
        try FileManager.default.removeItem(atPath: symlinkPath)
    }

    /// Returns true if the symlink target's .app bundle still exists on disk.
    static func validateAppBundle(symlinkAt path: String) -> Bool {
        let fm = FileManager.default
        guard let resolved = try? fm.destinationOfSymbolicLink(atPath: path) else { return true }
        let appPath = URL(fileURLWithPath: resolved)
            .deletingLastPathComponent()  // MacOS
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // .app
        return fm.fileExists(atPath: appPath.path)
    }

    static var manualInstallCommand: String {
        guard let execPath = Bundle.main.executablePath else { return "" }
        return "sudo ln -sf '\(execPath)' \(symlinkPath)"
    }

    static var manualUninstallCommand: String {
        "sudo rm \(symlinkPath)"
    }
}

enum CLIInstallError: LocalizedError {
    case noExecutablePath

    var errorDescription: String? {
        switch self {
        case .noExecutablePath:
            return "Could not determine the application executable path."
        }
    }
}
