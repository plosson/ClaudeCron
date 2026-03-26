import XCTest
@testable import ClaudeCron

@MainActor
final class ConfigIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccron-integration-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testWriteReadRoundTripWithAllScheduleTypes() throws {
        let config = ConfigService.shared
        var file = SettingsFile()

        file.tasks["daily"] = TaskDefinition(
            name: "Daily",
            prompt: "daily task",
            model: "sonnet",
            schedule: ScheduleDefinition(type: "Daily", hour: 9, minute: 30)
        )
        file.tasks["weekly"] = TaskDefinition(
            name: "Weekly",
            prompt: "weekly task",
            model: "opus",
            schedule: ScheduleDefinition(type: "Weekly", hour: 14, minute: 0, weekdays: [2, 4])
        )
        file.tasks["monthly"] = TaskDefinition(
            name: "Monthly",
            prompt: "monthly task",
            schedule: ScheduleDefinition(type: "Monthly", hour: 8, minute: 0, day: 15)
        )
        file.tasks["interval"] = TaskDefinition(
            name: "Interval",
            prompt: "interval task",
            schedule: ScheduleDefinition(type: "Interval", intervalMinutes: 45)
        )
        file.tasks["manual"] = TaskDefinition(
            name: "Manual",
            prompt: "manual task",
            schedule: ScheduleDefinition(type: "Manual")
        )

        try config.write(file, to: tempDir.path)
        let loaded = config.read(folder: tempDir.path)

        XCTAssertEqual(loaded.tasks.count, 5)

        let daily = try XCTUnwrap(loaded.tasks["daily"])
        XCTAssertEqual(daily.schedule.type, "Daily")
        XCTAssertEqual(daily.schedule.hour, 9)
        XCTAssertEqual(daily.schedule.minute, 30)

        let weekly = try XCTUnwrap(loaded.tasks["weekly"])
        XCTAssertEqual(weekly.schedule.weekdays, [2, 4])

        let monthly = try XCTUnwrap(loaded.tasks["monthly"])
        XCTAssertEqual(monthly.schedule.day, 15)

        let interval = try XCTUnwrap(loaded.tasks["interval"])
        XCTAssertEqual(interval.schedule.intervalMinutes, 45)
    }

    func testTaskDefinitionToClaudeTaskRoundTrip() {
        let def = TaskDefinition(
            name: "Test",
            prompt: "do it",
            path: "/tmp",
            model: "opus",
            permissionMode: "bypassPermissions",
            schedule: ScheduleDefinition(type: "Weekly", hour: 10, minute: 15, weekdays: [1, 3, 5]),
            isEnabled: false,
            sessionMode: "Resume Session",
            sessionId: "sess-123",
            allowedTools: ["Read", "Write"],
            disallowedTools: ["Bash"],
            notifyOnStart: true,
            notifyOnEnd: false
        )

        let task = ClaudeTask()
        task.taskId = "test-task"
        task.sourceFolder = "/Users/me/project"
        task.update(from: def, resolvedPath: "/tmp")

        let roundTripped = task.toTaskDefinition(isGlobal: true)

        XCTAssertEqual(roundTripped.name, def.name)
        XCTAssertEqual(roundTripped.prompt, def.prompt)
        XCTAssertEqual(roundTripped.path, def.path)
        XCTAssertEqual(roundTripped.model, def.model)
        XCTAssertEqual(roundTripped.permissionMode, def.permissionMode)
        XCTAssertEqual(roundTripped.isEnabled, def.isEnabled)
        XCTAssertEqual(roundTripped.sessionMode, def.sessionMode)
        XCTAssertEqual(roundTripped.sessionId, def.sessionId)
        XCTAssertEqual(roundTripped.allowedTools, def.allowedTools)
        XCTAssertEqual(roundTripped.disallowedTools, def.disallowedTools)
        XCTAssertEqual(roundTripped.notifyOnStart, def.notifyOnStart)
        XCTAssertEqual(roundTripped.notifyOnEnd, def.notifyOnEnd)
        XCTAssertEqual(roundTripped.schedule.type, def.schedule.type)
        XCTAssertEqual(roundTripped.schedule.hour, def.schedule.hour)
        XCTAssertEqual(roundTripped.schedule.minute, def.schedule.minute)
        XCTAssertEqual(roundTripped.schedule.weekdays, def.schedule.weekdays)
    }

    func testGlobalTaskIncludesPath() throws {
        var file = SettingsFile()
        var task = TaskDefinition(name: "Global", prompt: "hello")
        task.path = "/Users/me/project"
        file.tasks["global-task"] = task

        let config = ConfigService.shared
        try config.write(file, to: tempDir.path)
        let loaded = config.read(folder: tempDir.path)
        XCTAssertEqual(loaded.tasks["global-task"]?.path, "/Users/me/project")
    }

    func testProjectLocalTaskOmitsPath() {
        let task = ClaudeTask(name: "Local", prompt: "hello", directory: "/Users/me/project")
        task.taskId = "local-task"
        task.sourceFolder = "/Users/me/project"

        let def = task.toTaskDefinition(isGlobal: false)
        XCTAssertNil(def.path)
    }

    func testModifyTaskAndWriteBack() throws {
        let config = ConfigService.shared

        var file = SettingsFile()
        file.tasks["my-task"] = TaskDefinition(name: "Original", prompt: "first")
        try config.write(file, to: tempDir.path)

        var loaded = config.read(folder: tempDir.path)
        loaded.tasks["my-task"]?.name = "Updated"
        loaded.tasks["my-task"]?.prompt = "second"
        try config.write(loaded, to: tempDir.path)

        let reloaded = config.read(folder: tempDir.path)
        XCTAssertEqual(reloaded.tasks["my-task"]?.name, "Updated")
        XCTAssertEqual(reloaded.tasks["my-task"]?.prompt, "second")
    }

    func testDeleteTaskFromJSON() throws {
        let config = ConfigService.shared

        var file = SettingsFile()
        file.tasks["task-a"] = TaskDefinition(name: "A", prompt: "a")
        file.tasks["task-b"] = TaskDefinition(name: "B", prompt: "b")
        try config.write(file, to: tempDir.path)

        var loaded = config.read(folder: tempDir.path)
        loaded.tasks.removeValue(forKey: "task-a")
        try config.write(loaded, to: tempDir.path)

        let reloaded = config.read(folder: tempDir.path)
        XCTAssertNil(reloaded.tasks["task-a"])
        XCTAssertNotNil(reloaded.tasks["task-b"])
    }

    func testCompositeKeyIsStable() {
        let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "my-task"

        let key1 = task.compositeKey
        let key2 = task.compositeKey
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key1, "/Users/me/project::my-task")
    }

    func testLaunchdLabelDeterministic() {
        let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "my-task"

        let label1 = LaunchdService.shared.plistLabel(for: task)
        let label2 = LaunchdService.shared.plistLabel(for: task)
        XCTAssertEqual(label1, label2)
        XCTAssertTrue(label1.hasPrefix("com.claudecron.task."))
    }

    func testFullWriteConvertRoundTrip() throws {
        // Write a settings file
        let config = ConfigService.shared
        var file = SettingsFile()
        file.tasks["test"] = TaskDefinition(
            name: "Full Test",
            prompt: "do everything",
            model: "opus",
            permissionMode: "acceptEdits",
            schedule: ScheduleDefinition(type: "Daily", hour: 8, minute: 0),
            isEnabled: true,
            allowedTools: ["Read"],
            notifyOnEnd: true
        )
        try config.write(file, to: tempDir.path)

        // Read it back
        let loaded = config.read(folder: tempDir.path)
        let def = try XCTUnwrap(loaded.tasks["test"])

        // Convert to ClaudeTask
        let task = ClaudeTask()
        task.taskId = "test"
        task.sourceFolder = tempDir.path
        task.update(from: def, resolvedPath: tempDir.path)

        // Verify fields
        XCTAssertEqual(task.name, "Full Test")
        XCTAssertEqual(task.model, "opus")
        XCTAssertEqual(task.permissionMode, "acceptEdits")

        // Convert back and write
        let isGlobal = false
        var updatedFile = config.read(folder: tempDir.path)
        updatedFile.tasks["test"] = task.toTaskDefinition(isGlobal: isGlobal)
        try config.write(updatedFile, to: tempDir.path)

        // Read again and verify
        let final_ = config.read(folder: tempDir.path)
        let finalDef = try XCTUnwrap(final_.tasks["test"])
        XCTAssertEqual(finalDef.name, "Full Test")
        XCTAssertEqual(finalDef.model, "opus")
        XCTAssertEqual(finalDef.permissionMode, "acceptEdits")
        XCTAssertNil(finalDef.path) // project-local, no path
    }
}
