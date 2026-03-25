import XCTest
@testable import ClaudeCron

final class ClaudeTaskTests: XCTestCase {

    func testDefaultInit() {
        let task = ClaudeTask()
        XCTAssertEqual(task.name, "")
        XCTAssertEqual(task.prompt, "")
        XCTAssertEqual(task.directory, "")
        XCTAssertEqual(task.model, ClaudeModel.sonnet.rawValue)
        XCTAssertEqual(task.permissionMode, PermissionMode.default_.rawValue)
        XCTAssertTrue(task.isEnabled)
        XCTAssertEqual(task.sessionMode, SessionMode.new.rawValue)
        XCTAssertEqual(task.allowedTools, "")
        XCTAssertEqual(task.disallowedTools, "")
        XCTAssertFalse(task.notifyOnStart)
        XCTAssertTrue(task.notifyOnEnd)
        XCTAssertNotNil(task.id)
        XCTAssertTrue(task.runs.isEmpty)
    }

    func testCustomInit() {
        let task = ClaudeTask(
            name: "Test Task",
            prompt: "do something",
            directory: "/tmp",
            model: .opus,
            permissionMode: .bypass,
            isEnabled: false,
            sessionMode: .resume,
            allowedTools: "Read,Write",
            disallowedTools: "Bash",
            notifyOnStart: true,
            notifyOnEnd: false
        )
        XCTAssertEqual(task.name, "Test Task")
        XCTAssertEqual(task.prompt, "do something")
        XCTAssertEqual(task.directory, "/tmp")
        XCTAssertEqual(task.model, "opus")
        XCTAssertEqual(task.permissionMode, "bypassPermissions")
        XCTAssertFalse(task.isEnabled)
        XCTAssertEqual(task.sessionMode, SessionMode.resume.rawValue)
        XCTAssertEqual(task.allowedTools, "Read,Write")
        XCTAssertEqual(task.disallowedTools, "Bash")
        XCTAssertTrue(task.notifyOnStart)
        XCTAssertFalse(task.notifyOnEnd)
    }

    func testSchedulePropertyRoundTrip() {
        let task = ClaudeTask()
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = [1, 4, 7]
        schedule.intervalMinutes = 90
        task.schedule = schedule
        let retrieved = task.schedule
        XCTAssertEqual(retrieved.type, .weekly)
        XCTAssertEqual(retrieved.weekdays, [1, 4, 7])
        XCTAssertEqual(retrieved.intervalMinutes, 90)
    }

    func testSchedulePropertyWithNilData() {
        let task = ClaudeTask()
        task.scheduleData = nil
        let schedule = task.schedule
        XCTAssertEqual(schedule.type, .daily)
        XCTAssertTrue(schedule.weekdays.isEmpty)
    }

    func testSchedulePropertyWithCorruptData() {
        let task = ClaudeTask()
        task.scheduleData = Data("not json".utf8)
        let schedule = task.schedule
        XCTAssertEqual(schedule.type, .daily)
    }

    func testClaudeModelAllCases() {
        XCTAssertEqual(ClaudeModel.allCases.count, 3)
        XCTAssertEqual(ClaudeModel.opus.rawValue, "opus")
        XCTAssertEqual(ClaudeModel.sonnet.rawValue, "sonnet")
        XCTAssertEqual(ClaudeModel.haiku.rawValue, "haiku")
    }

    func testPermissionModeAllCases() {
        XCTAssertEqual(PermissionMode.allCases.count, 4)
        XCTAssertEqual(PermissionMode.bypass.rawValue, "bypassPermissions")
    }

    func testSessionModeAllCases() {
        XCTAssertEqual(SessionMode.allCases.count, 3)
        XCTAssertEqual(SessionMode.new.rawValue, "New Session")
        XCTAssertEqual(SessionMode.resume.rawValue, "Resume Session")
        XCTAssertEqual(SessionMode.fork.rawValue, "Fork Session")
    }

    func testSourceFolderAndTaskId() {
        let task = ClaudeTask()
        task.sourceFolder = "/Users/me/project"
        task.taskId = "my-task"
        XCTAssertEqual(task.sourceFolder, "/Users/me/project")
        XCTAssertEqual(task.taskId, "my-task")
    }

    func testCompositeKey() {
        let task = ClaudeTask()
        task.sourceFolder = "/Users/me/project"
        task.taskId = "daily-cleanup"
        XCTAssertEqual(task.compositeKey, "/Users/me/project::daily-cleanup")
    }

    func testToTaskDefinition() {
        let task = ClaudeTask(
            name: "Test",
            prompt: "do it",
            directory: "/tmp",
            model: .opus,
            permissionMode: .bypass,
            isEnabled: false,
            allowedTools: "Read,Write",
            disallowedTools: "Bash",
            notifyOnStart: true,
            notifyOnEnd: false
        )
        task.taskId = "test-task"
        task.sourceFolder = NSHomeDirectory()

        let def = task.toTaskDefinition(isGlobal: true)
        XCTAssertEqual(def.name, "Test")
        XCTAssertEqual(def.prompt, "do it")
        XCTAssertEqual(def.path, "/tmp")
        XCTAssertEqual(def.model, "opus")
        XCTAssertEqual(def.permissionMode, "bypassPermissions")
        XCTAssertFalse(def.isEnabled)
        XCTAssertEqual(def.allowedTools, ["Read", "Write"])
        XCTAssertEqual(def.disallowedTools, ["Bash"])
        XCTAssertTrue(def.notifyOnStart)
        XCTAssertFalse(def.notifyOnEnd)
    }

    func testToTaskDefinitionProjectLocal() {
        let task = ClaudeTask(
            name: "Test",
            prompt: "do it",
            directory: "/Users/me/project"
        )
        task.taskId = "test-task"
        task.sourceFolder = "/Users/me/project"

        let def = task.toTaskDefinition(isGlobal: false)
        XCTAssertNil(def.path)
    }

    func testUpdateFromDefinition() {
        let task = ClaudeTask()
        let def = TaskDefinition(
            name: "Updated",
            prompt: "new prompt",
            path: "/new/path",
            model: "opus",
            permissionMode: "bypassPermissions"
        )
        task.update(from: def, resolvedPath: "/new/path")
        XCTAssertEqual(task.name, "Updated")
        XCTAssertEqual(task.prompt, "new prompt")
        XCTAssertEqual(task.directory, "/new/path")
        XCTAssertEqual(task.model, "opus")
        XCTAssertEqual(task.permissionMode, "bypassPermissions")
    }
}
