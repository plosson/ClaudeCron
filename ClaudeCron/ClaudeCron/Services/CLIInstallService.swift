import Foundation

enum CLIInstallService {
    static let cliName = "ccron"
    static let symlinkPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/\(cliName)").path

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
        let binDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        if !fm.fileExists(atPath: binDir) {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }
        try? fm.removeItem(atPath: symlinkPath)
        try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: execPath)
        addToPathIfNeeded()
    }

    private static func addToPathIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathLine = "export PATH=\"$HOME/.local/bin:$PATH\""

        // Check common shell config files
        let candidates: [(path: URL, exists: Bool)] = [
            ".zshrc", ".bashrc", ".bash_profile", ".profile"
        ].map { (home.appendingPathComponent($0), FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path)) }

        // Pick the first existing file, defaulting to .zshrc
        let target = candidates.first(where: { $0.exists })?.path ?? home.appendingPathComponent(".zshrc")

        // Check if already configured
        if let contents = try? String(contentsOf: target, encoding: .utf8),
           contents.contains(".local/bin") {
            return
        }

        // Append the PATH export
        if let handle = try? FileHandle(forWritingTo: target) {
            handle.seekToEndOfFile()
            handle.write("\n# Added by Claude Cron\n\(pathLine)\n".data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? "\n# Added by Claude Cron\n\(pathLine)\n".write(to: target, atomically: true, encoding: .utf8)
        }
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
        return "mkdir -p ~/.local/bin && ln -sf '\(execPath)' \(symlinkPath)"
    }

    static var manualUninstallCommand: String {
        "rm \(symlinkPath)"
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
