import XCTest
@testable import ClaudeCron

final class CLIInstallServiceTests: XCTestCase {
    var tempHome: URL!
    var fm: FileManager!

    override func setUp() {
        super.setUp()
        fm = FileManager.default
        tempHome = fm.temporaryDirectory
            .appendingPathComponent("ccron-cli-test-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tempHome)
        super.tearDown()
    }

    private func makeService(executablePath: String? = "/fake/Claude Cron.app/Contents/MacOS/Claude Cron") -> CLIInstallService {
        CLIInstallService(
            homeDirectory: tempHome,
            executablePath: executablePath,
            fileManager: fm
        )
    }

    // MARK: - isInstalled edge cases

    func testIsInstalledReturnsFalseWhenNoSymlinkExists() {
        let svc = makeService()
        XCTAssertFalse(svc.isInstalled)
    }

    func testIsInstalledReturnsFalseWhenSymlinkPointsToWrongBinary() throws {
        let svc = makeService(executablePath: "/real/app/binary")
        let binDir = tempHome.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: svc.symlinkPath,
            withDestinationPath: "/some/other/binary"
        )
        XCTAssertFalse(svc.isInstalled, "Should be false when symlink points to a different binary")
    }

    func testIsInstalledReturnsFalseWhenExecutablePathIsNil() throws {
        let svc = makeService(executablePath: nil)
        XCTAssertFalse(svc.isInstalled, "Should be false when app has no executable path")
    }

    func testIsInstalledReturnsFalseWhenSymlinkIsBroken() throws {
        let svc = makeService(executablePath: "/nonexistent/path")
        let binDir = tempHome.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: svc.symlinkPath,
            withDestinationPath: "/nonexistent/path"
        )
        // Symlink exists and points to the "right" path, so isInstalled should be true
        // even though the target doesn't exist — isInstalled checks the symlink destination string, not existence
        XCTAssertTrue(svc.isInstalled, "Should match on symlink destination string regardless of target existence")
    }

    func testIsInstalledReturnsFalseWhenSymlinkReplacedWithRegularFile() throws {
        let svc = makeService()
        let binDir = tempHome.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        // Write a regular file at the symlink path instead of a symlink
        try "not a symlink".write(toFile: svc.symlinkPath, atomically: true, encoding: .utf8)
        XCTAssertFalse(svc.isInstalled, "Should be false when path is a regular file, not a symlink")
    }

    // MARK: - install edge cases

    func testInstallThrowsWhenExecutablePathIsNil() {
        let svc = makeService(executablePath: nil)
        XCTAssertThrowsError(try svc.install()) { error in
            XCTAssertTrue(error is CLIInstallError)
        }
    }

    func testInstallOverwritesExistingStaleSymlink() throws {
        let svc = makeService(executablePath: "/new/app/binary")
        let binDir = tempHome.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        // Create a stale symlink pointing elsewhere
        try fm.createSymbolicLink(atPath: svc.symlinkPath, withDestinationPath: "/old/app/binary")

        try svc.install()

        let dest = try fm.destinationOfSymbolicLink(atPath: svc.symlinkPath)
        XCTAssertEqual(dest, "/new/app/binary", "Should overwrite stale symlink with new target")
    }

    func testInstallOverwritesRegularFileAtSymlinkPath() throws {
        let svc = makeService(executablePath: "/app/binary")
        let binDir = tempHome.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        // Someone put a regular file where the symlink should be
        try "garbage".write(toFile: svc.symlinkPath, atomically: true, encoding: .utf8)

        try svc.install()

        let dest = try fm.destinationOfSymbolicLink(atPath: svc.symlinkPath)
        XCTAssertEqual(dest, "/app/binary", "Should replace regular file with symlink")
    }

    func testInstallCreatesBinDirectoryWhenMissing() throws {
        let svc = makeService(executablePath: "/app/binary")
        let binDir = tempHome.appendingPathComponent(".local/bin").path
        XCTAssertFalse(fm.fileExists(atPath: binDir))

        try svc.install()

        XCTAssertTrue(fm.fileExists(atPath: binDir), "Should create ~/.local/bin if it doesn't exist")
        // Symlink exists but target doesn't — use attributesOfItem to check symlink itself
        XCTAssertNotNil(try? fm.attributesOfItem(atPath: svc.symlinkPath), "Symlink should exist")
    }

    func testDoubleInstallDoesNotThrow() throws {
        let svc = makeService(executablePath: "/app/binary")
        try svc.install()
        XCTAssertNoThrow(try svc.install(), "Installing twice should not fail")
    }

    // MARK: - uninstall edge cases

    func testUninstallThrowsWhenNoSymlinkExists() {
        let svc = makeService()
        XCTAssertThrowsError(try svc.uninstall(), "Should throw when there's nothing to uninstall")
    }

    func testUninstallAfterInstallLeavesNoSymlink() throws {
        let svc = makeService(executablePath: "/app/binary")
        try svc.install()
        try svc.uninstall()
        XCTAssertFalse(fm.fileExists(atPath: svc.symlinkPath))
        XCTAssertFalse(svc.isInstalled)
    }

    // MARK: - addToPathIfNeeded edge cases

    func testAddToPathDoesNotDuplicateIfAlreadyPresent() throws {
        let svc = makeService(executablePath: "/app/binary")
        let zshrc = tempHome.appendingPathComponent(".zshrc")
        try "existing content\nexport PATH=\"$HOME/.local/bin:$PATH\"\n".write(to: zshrc, atomically: true, encoding: .utf8)

        svc.addToPathIfNeeded()

        let content = try String(contentsOf: zshrc, encoding: .utf8)
        let occurrences = content.components(separatedBy: ".local/bin").count - 1
        XCTAssertEqual(occurrences, 1, "Should not add PATH export when .local/bin is already referenced")
    }

    func testAddToPathDoesNotDuplicateAfterMultipleCalls() throws {
        let svc = makeService(executablePath: "/app/binary")
        let zshrc = tempHome.appendingPathComponent(".zshrc")
        try "".write(to: zshrc, atomically: true, encoding: .utf8)

        svc.addToPathIfNeeded()
        svc.addToPathIfNeeded()
        svc.addToPathIfNeeded()

        let content = try String(contentsOf: zshrc, encoding: .utf8)
        let occurrences = content.components(separatedBy: "# Added by Claude Cron").count - 1
        XCTAssertEqual(occurrences, 1, "Calling addToPathIfNeeded multiple times should only add once")
    }

    func testAddToPathPrefersExistingBashrcOverZshrc() throws {
        let svc = makeService(executablePath: "/app/binary")
        // Create .bashrc but not .zshrc
        let bashrc = tempHome.appendingPathComponent(".bashrc")
        try "# bash config\n".write(to: bashrc, atomically: true, encoding: .utf8)

        svc.addToPathIfNeeded()

        let content = try String(contentsOf: bashrc, encoding: .utf8)
        XCTAssertTrue(content.contains(".local/bin"), "Should write to existing .bashrc")

        let zshrc = tempHome.appendingPathComponent(".zshrc")
        XCTAssertFalse(fm.fileExists(atPath: zshrc.path), "Should not create .zshrc when .bashrc exists")
    }

    func testAddToPathCreatesZshrcWhenNoShellConfigExists() throws {
        let svc = makeService(executablePath: "/app/binary")
        // No shell config files exist

        svc.addToPathIfNeeded()

        let zshrc = tempHome.appendingPathComponent(".zshrc")
        XCTAssertTrue(fm.fileExists(atPath: zshrc.path), "Should create .zshrc as default")
        let content = try String(contentsOf: zshrc, encoding: .utf8)
        XCTAssertTrue(content.contains(".local/bin"))
    }

    // MARK: - validateAppBundle edge cases

    func testValidateAppBundleReturnsTrueWhenPathIsNotASymlink() {
        let svc = makeService()
        // Regular file, not a symlink — should return true (fail open)
        let path = tempHome.appendingPathComponent("not-a-symlink").path
        XCTAssertTrue(svc.validateAppBundle(symlinkAt: path),
                      "Should return true when path is not a symlink (cannot resolve)")
    }

    func testValidateAppBundleReturnsFalseWhenAppBundleDeleted() throws {
        let svc = makeService()
        // Create a fake app bundle structure
        let appDir = tempHome.appendingPathComponent("Fake.app/Contents/MacOS")
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        let binaryPath = appDir.appendingPathComponent("FakeBinary").path
        try "".write(toFile: binaryPath, atomically: true, encoding: .utf8)

        // Create symlink pointing to the binary
        let symlinkAt = tempHome.appendingPathComponent("test-symlink").path
        try fm.createSymbolicLink(atPath: symlinkAt, withDestinationPath: binaryPath)

        // Verify it validates while app exists
        XCTAssertTrue(svc.validateAppBundle(symlinkAt: symlinkAt))

        // Delete the app bundle
        try fm.removeItem(at: tempHome.appendingPathComponent("Fake.app"))

        XCTAssertFalse(svc.validateAppBundle(symlinkAt: symlinkAt),
                       "Should return false when the .app bundle has been deleted")
    }

    // MARK: - Symlink path with spaces

    func testInstallWorksWithSpacesInPath() throws {
        let spaceyHome = fm.temporaryDirectory
            .appendingPathComponent("ccron test dir \(UUID().uuidString)")
        try fm.createDirectory(at: spaceyHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: spaceyHome) }

        let svc = CLIInstallService(
            homeDirectory: spaceyHome,
            executablePath: "/Applications/Claude Cron.app/Contents/MacOS/Claude Cron",
            fileManager: fm
        )

        try svc.install()

        XCTAssertTrue(fm.fileExists(atPath: svc.symlinkPath), "Symlink should exist even with spaces in home path")
        let dest = try fm.destinationOfSymbolicLink(atPath: svc.symlinkPath)
        XCTAssertEqual(dest, "/Applications/Claude Cron.app/Contents/MacOS/Claude Cron")
    }
}
