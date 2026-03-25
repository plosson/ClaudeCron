import XCTest
@testable import ClaudeCron

final class ConfigServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccron-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var settingsPath: String {
        tempDir.appendingPathComponent(".ccron/settings.json").path
    }

    func testReadNonExistentFileReturnsEmptySettingsFile() throws {
        let service = ConfigService()
        let result = service.read(folder: tempDir.path)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testWriteCreatesDirectoryAndFile() throws {
        let service = ConfigService()
        var file = SettingsFile()
        file.tasks["test"] = TaskDefinition(name: "Test", prompt: "hello")
        try service.write(file, to: tempDir.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsPath))
    }

    func testWriteThenReadRoundTrip() throws {
        let service = ConfigService()
        var file = SettingsFile()
        file.tasks["my-task"] = TaskDefinition(name: "My Task", prompt: "do stuff")
        try service.write(file, to: tempDir.path)

        let loaded = service.read(folder: tempDir.path)
        XCTAssertEqual(loaded.tasks.count, 1)
        XCTAssertEqual(loaded.tasks["my-task"]?.name, "My Task")
        XCTAssertEqual(loaded.tasks["my-task"]?.prompt, "do stuff")
    }

    func testWriteProducesPrettyPrintedJSON() throws {
        let service = ConfigService()
        var file = SettingsFile()
        file.tasks["x"] = TaskDefinition(name: "X", prompt: "Y")
        try service.write(file, to: tempDir.path)

        let content = try String(contentsOfFile: settingsPath)
        XCTAssertTrue(content.contains("\n"))
        XCTAssertTrue(content.contains("  "))
    }

    func testReadCorruptFileReturnsEmpty() {
        let ccronDir = tempDir.appendingPathComponent(".ccron")
        try! FileManager.default.createDirectory(at: ccronDir, withIntermediateDirectories: true)
        try! "not json".write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let service = ConfigService()
        let result = service.read(folder: tempDir.path)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testSettingsFilePath() {
        let service = ConfigService()
        let path = service.settingsFilePath(for: "/Users/me/project")
        XCTAssertEqual(path, "/Users/me/project/.ccron/settings.json")
    }
}
