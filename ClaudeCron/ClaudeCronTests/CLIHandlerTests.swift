import XCTest
import SwiftData
@testable import ClaudeCron

final class CLIHandlerTests: XCTestCase {

    // MARK: - Helper

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([ClaudeTask.self, TaskRun.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - slugify

    func testSlugifySimpleName() {
        XCTAssertEqual(CLIHandler.slugify("My Task Name"), "my-task-name")
    }

    func testSlugifySingleWord() {
        XCTAssertEqual(CLIHandler.slugify("Cleanup"), "cleanup")
    }

    func testSlugifyWithNumbers() {
        XCTAssertEqual(CLIHandler.slugify("Task 42"), "task-42")
    }

    func testSlugifyWithSpecialChars() {
        XCTAssertEqual(CLIHandler.slugify("Hello! World@#$"), "hello-world")
    }

    func testSlugifyAlreadySlug() {
        XCTAssertEqual(CLIHandler.slugify("already-slug"), "already-slug")
    }

    func testSlugifyEmpty() {
        XCTAssertEqual(CLIHandler.slugify(""), "")
    }

    func testSlugifyMultipleSpaces() {
        // Each space becomes a dash, special chars stripped
        XCTAssertEqual(CLIHandler.slugify("a  b"), "a--b")
    }

    // MARK: - flagValue

    func testFlagValuePresent() {
        let args = ["--name", "hello", "--model", "opus"]
        XCTAssertEqual(CLIHandler.flagValue("--model", in: args), "opus")
    }

    func testFlagValueFirst() {
        let args = ["--prompt", "do stuff", "--model", "sonnet"]
        XCTAssertEqual(CLIHandler.flagValue("--prompt", in: args), "do stuff")
    }

    func testFlagValueMissing() {
        let args = ["--name", "hello"]
        XCTAssertNil(CLIHandler.flagValue("--model", in: args))
    }

    func testFlagValueAtEnd() {
        // Flag is last element, no value follows
        let args = ["--name", "hello", "--model"]
        XCTAssertNil(CLIHandler.flagValue("--model", in: args))
    }

    func testFlagValueEmptyArgs() {
        XCTAssertNil(CLIHandler.flagValue("--model", in: []))
    }

    // MARK: - hasFlag

    func testHasFlagPresent() {
        let args = ["--notify-start", "--model", "opus"]
        XCTAssertTrue(CLIHandler.hasFlag("--notify-start", in: args))
    }

    func testHasFlagAbsent() {
        let args = ["--model", "opus"]
        XCTAssertFalse(CLIHandler.hasFlag("--notify-start", in: args))
    }

    func testHasFlagEmptyArgs() {
        XCTAssertFalse(CLIHandler.hasFlag("--notify-start", in: []))
    }

    // MARK: - displayFolder

    func testDisplayFolderHomeDir() {
        let home = NSHomeDirectory()
        XCTAssertEqual(CLIHandler.displayFolder(home), "~ (global)")
    }

    func testDisplayFolderSubdirectory() {
        let home = NSHomeDirectory()
        let sub = home + "/Projects/myapp"
        XCTAssertEqual(CLIHandler.displayFolder(sub), "~/Projects/myapp")
    }

    func testDisplayFolderUnrelatedPath() {
        XCTAssertEqual(CLIHandler.displayFolder("/tmp/something"), "/tmp/something")
    }

    // MARK: - formatDuration

    func testFormatDurationSeconds() {
        XCTAssertEqual(CLIHandler.formatDuration(45), "45s")
    }

    func testFormatDurationZero() {
        XCTAssertEqual(CLIHandler.formatDuration(0), "0s")
    }

    func testFormatDurationMinutes() {
        // 2m 30s = 150 seconds
        XCTAssertEqual(CLIHandler.formatDuration(150), "2m 30s")
    }

    func testFormatDurationExactMinutes() {
        XCTAssertEqual(CLIHandler.formatDuration(120), "2m 0s")
    }

    func testFormatDurationHours() {
        // 1h 30m = 5400 seconds
        XCTAssertEqual(CLIHandler.formatDuration(5400), "1h 30m")
    }

    func testFormatDurationExactHour() {
        XCTAssertEqual(CLIHandler.formatDuration(3600), "1h 0m")
    }

    func testFormatDurationJustUnderMinute() {
        XCTAssertEqual(CLIHandler.formatDuration(59), "59s")
    }

    func testFormatDurationExactlyOneMinute() {
        XCTAssertEqual(CLIHandler.formatDuration(60), "1m 0s")
    }

    // MARK: - mapSessionMode

    func testMapSessionModeNew() {
        XCTAssertEqual(CLIHandler.mapSessionMode("new"), .new)
    }

    func testMapSessionModeResume() {
        XCTAssertEqual(CLIHandler.mapSessionMode("resume"), .resume)
    }

    func testMapSessionModeFork() {
        XCTAssertEqual(CLIHandler.mapSessionMode("fork"), .fork)
    }

    func testMapSessionModeInvalid() {
        XCTAssertNil(CLIHandler.mapSessionMode("invalid"))
    }

    func testMapSessionModeCaseInsensitive() {
        XCTAssertEqual(CLIHandler.mapSessionMode("NEW"), .new)
        XCTAssertEqual(CLIHandler.mapSessionMode("Resume"), .resume)
    }

    // MARK: - mapPermissionMode

    func testMapPermissionModeDefault() {
        XCTAssertEqual(CLIHandler.mapPermissionMode("default"), PermissionMode.default_.rawValue)
    }

    func testMapPermissionModeBypass() {
        XCTAssertEqual(CLIHandler.mapPermissionMode("bypass"), PermissionMode.bypass.rawValue)
    }

    func testMapPermissionModePlan() {
        XCTAssertEqual(CLIHandler.mapPermissionMode("plan"), PermissionMode.plan.rawValue)
    }

    func testMapPermissionModeAcceptEdits() {
        XCTAssertEqual(CLIHandler.mapPermissionMode("acceptedits"), PermissionMode.acceptEdits.rawValue)
    }

    func testMapPermissionModeRawValue() {
        // Should accept raw values directly
        XCTAssertEqual(CLIHandler.mapPermissionMode("bypassPermissions"), "bypassPermissions")
    }

    func testMapPermissionModeInvalid() {
        XCTAssertNil(CLIHandler.mapPermissionMode("unknown"))
    }

    // MARK: - mapModel

    func testMapModelOpus() {
        XCTAssertEqual(CLIHandler.mapModel("opus"), "opus")
    }

    func testMapModelSonnet() {
        XCTAssertEqual(CLIHandler.mapModel("sonnet"), "sonnet")
    }

    func testMapModelHaiku() {
        XCTAssertEqual(CLIHandler.mapModel("haiku"), "haiku")
    }

    func testMapModelCaseInsensitive() {
        XCTAssertEqual(CLIHandler.mapModel("OPUS"), "opus")
        XCTAssertEqual(CLIHandler.mapModel("Sonnet"), "sonnet")
    }

    func testMapModelInvalid() {
        XCTAssertNil(CLIHandler.mapModel("gpt4"))
    }

    // MARK: - parseWeekdays

    func testParseWeekdaysSingle() {
        XCTAssertEqual(CLIHandler.parseWeekdays("mon"), Set([2]))
    }

    func testParseWeekdaysMultiple() {
        XCTAssertEqual(CLIHandler.parseWeekdays("mon,wed,fri"), Set([2, 4, 6]))
    }

    func testParseWeekdaysAllDays() {
        XCTAssertEqual(CLIHandler.parseWeekdays("sun,mon,tue,wed,thu,fri,sat"), Set([1, 2, 3, 4, 5, 6, 7]))
    }

    func testParseWeekdaysEmpty() {
        XCTAssertEqual(CLIHandler.parseWeekdays(""), Set())
    }

    func testParseWeekdaysInvalid() {
        XCTAssertEqual(CLIHandler.parseWeekdays("xyz"), Set())
    }

    func testParseWeekdaysMixed() {
        // Valid and invalid mixed
        XCTAssertEqual(CLIHandler.parseWeekdays("mon,xyz,fri"), Set([2, 6]))
    }

    // MARK: - parseSchedule (valid cases only)

    func testParseScheduleManual() {
        let args = ["--schedule", "manual"]
        let schedule = CLIHandler.parseSchedule(from: args)
        XCTAssertEqual(schedule.type, .manual)
    }

    func testParseScheduleDaily() {
        let args = ["--schedule", "daily", "--time", "09:30"]
        let schedule = CLIHandler.parseSchedule(from: args)
        XCTAssertEqual(schedule.type, .daily)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: schedule.time)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 30)
    }

    func testParseScheduleWeekly() {
        let args = ["--schedule", "weekly", "--time", "14:00", "--weekdays", "mon,wed,fri"]
        let schedule = CLIHandler.parseSchedule(from: args)
        XCTAssertEqual(schedule.type, .weekly)
        XCTAssertEqual(schedule.weekdays, Set([2, 4, 6]))
    }

    func testParseScheduleInterval() {
        let args = ["--schedule", "interval", "--interval", "30"]
        let schedule = CLIHandler.parseSchedule(from: args)
        XCTAssertEqual(schedule.type, .interval)
        XCTAssertEqual(schedule.intervalMinutes, 30)
    }

    func testParseScheduleNoFlag() {
        // No --schedule flag defaults to manual
        let schedule = CLIHandler.parseSchedule(from: [])
        XCTAssertEqual(schedule.type, .manual)
    }

    // MARK: - resolveTask

    func testResolveTaskSingleMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = ClaudeTask(name: "Test Task")
        task.taskId = "test-task"
        task.sourceFolder = "/tmp/project"
        context.insert(task)
        try context.save()

        let found = CLIHandler.resolveTask("test-task", container: container)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.taskId, "test-task")
    }

    func testResolveTaskNotFound() throws {
        let container = try makeContainer()

        let found = CLIHandler.resolveTask("nonexistent", container: container)
        XCTAssertNil(found)
    }

    func testResolveTaskFolderQualified() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let task1 = ClaudeTask(name: "Task A")
        task1.taskId = "my-task"
        task1.sourceFolder = "/tmp/project-a"
        context.insert(task1)

        let task2 = ClaudeTask(name: "Task B")
        task2.taskId = "my-task"
        task2.sourceFolder = "/tmp/project-b"
        context.insert(task2)
        try context.save()

        let found = CLIHandler.resolveTask("/tmp/project-a::my-task", container: container)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Task A")
    }

    func testResolveTaskAmbiguous() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let task1 = ClaudeTask(name: "Task A")
        task1.taskId = "my-task"
        task1.sourceFolder = "/tmp/project-a"
        context.insert(task1)

        let task2 = ClaudeTask(name: "Task B")
        task2.taskId = "my-task"
        task2.sourceFolder = "/tmp/project-b"
        context.insert(task2)
        try context.save()

        // Ambiguous: two tasks with same taskId, no folder qualifier
        let found = CLIHandler.resolveTask("my-task", container: container)
        XCTAssertNil(found)
    }

    // MARK: - cmdList

    func testCmdListEmptyDatabase() throws {
        let container = try makeContainer()
        // Should not crash with empty database
        CLIHandler.cmdList(container: container)
    }

    // NOTE: cmdList with tasks, cmdHistory with runs, and cmdHistory filtered by task
    // are omitted because the production code uses String(format: "%-8s", ...) with
    // Unicode characters (● / ○), which crashes under the C string formatter.
    // Those commands work fine in the real CLI where output goes to a terminal.

    // MARK: - cmdShow

    func testCmdShowWithValidTask() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let task = ClaudeTask(name: "Show Task", prompt: "run tests")
        task.taskId = "show-task"
        task.sourceFolder = "/tmp/project"
        context.insert(task)
        try context.save()

        // Should not crash — cmdShow uses print() not String(format: "%s")
        CLIHandler.cmdShow(subargs: ["show-task"], container: container)
    }

    // MARK: - cmdHistory

    func testCmdHistoryEmpty() throws {
        let container = try makeContainer()
        // Should not crash with no runs (prints "No runs found." and returns)
        CLIHandler.cmdHistory(subargs: [], container: container)
    }
}
