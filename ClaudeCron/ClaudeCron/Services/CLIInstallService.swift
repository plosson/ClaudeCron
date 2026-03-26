import Foundation

struct CLIInstallService {
    static let cliName = "ccron"

    let homeDirectory: URL
    let executablePath: String?
    let fileManager: FileManager

    var symlinkPath: String {
        homeDirectory.appendingPathComponent(".local/bin/\(Self.cliName)").path
    }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePath: String? = Bundle.main.executablePath,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.executablePath = executablePath
        self.fileManager = fileManager
    }

    // MARK: - Static convenience (preserves existing call sites)

    private static let _shared = CLIInstallService()

    static var symlinkPath: String { _shared.symlinkPath }

    static var isInstalled: Bool { _shared.isInstalled }

    static func install() throws { try _shared.install() }

    static func uninstall() throws { try _shared.uninstall() }

    static func validateAppBundle(symlinkAt path: String) -> Bool {
        _shared.validateAppBundle(symlinkAt: path)
    }

    static var manualInstallCommand: String { _shared.manualInstallCommand }

    static var manualUninstallCommand: String { _shared.manualUninstallCommand }

    // MARK: - Instance methods

    var isInstalled: Bool {
        guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath),
              let execPath = executablePath else { return false }
        return dest == execPath
    }

    func install() throws {
        guard let execPath = executablePath else {
            throw CLIInstallError.noExecutablePath
        }
        let binDir = homeDirectory.appendingPathComponent(".local/bin").path
        if !fileManager.fileExists(atPath: binDir) {
            try fileManager.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }
        try? fileManager.removeItem(atPath: symlinkPath)
        try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: execPath)
        addToPathIfNeeded()
    }

    func addToPathIfNeeded() {
        let pathLine = "export PATH=\"$HOME/.local/bin:$PATH\""

        let candidates: [(path: URL, exists: Bool)] = [
            ".zshrc", ".bashrc", ".bash_profile", ".profile"
        ].map { (homeDirectory.appendingPathComponent($0), fileManager.fileExists(atPath: homeDirectory.appendingPathComponent($0).path)) }

        let target = candidates.first(where: { $0.exists })?.path ?? homeDirectory.appendingPathComponent(".zshrc")

        if let contents = try? String(contentsOf: target, encoding: .utf8),
           contents.contains(".local/bin") {
            return
        }

        if let handle = try? FileHandle(forWritingTo: target) {
            handle.seekToEndOfFile()
            handle.write("\n# Added by Claude Cron\n\(pathLine)\n".data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? "\n# Added by Claude Cron\n\(pathLine)\n".write(to: target, atomically: true, encoding: .utf8)
        }
    }

    func uninstall() throws {
        try fileManager.removeItem(atPath: symlinkPath)
    }

    func validateAppBundle(symlinkAt path: String) -> Bool {
        guard let resolved = try? fileManager.destinationOfSymbolicLink(atPath: path) else { return true }
        let appPath = URL(fileURLWithPath: resolved)
            .deletingLastPathComponent()  // MacOS
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // .app
        return fileManager.fileExists(atPath: appPath.path)
    }

    var manualInstallCommand: String {
        guard let execPath = executablePath else { return "" }
        return "mkdir -p ~/.local/bin && ln -sf '\(execPath)' \(symlinkPath)"
    }

    var manualUninstallCommand: String {
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
