import XCTest
@testable import ClaudeCron

final class LaunchdServiceTests: XCTestCase {

    private let service = LaunchdService.shared

    func testPlistContainsLabel() {
        let task = ClaudeTask(name: "Test")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "test-task"
        let plist = service.buildPlist(task: task)
        let expectedLabel = service.plistLabel(for: task)
        XCTAssertEqual(plist["Label"] as? String, expectedLabel)
    }

    func testPlistContainsProgramArguments() {
        let task = ClaudeTask(name: "Test")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "test-task"
        let plist = service.buildPlist(task: task)
        let args = plist["ProgramArguments"] as? [String]
        XCTAssertNotNil(args)
        XCTAssertTrue(args!.contains("--run-task"))
        XCTAssertTrue(args!.contains("--source-folder"))
        XCTAssertTrue(args!.contains(task.sourceFolder))
        XCTAssertTrue(args!.contains("--task-id"))
        XCTAssertTrue(args!.contains(task.taskId))
    }

    func testPlistRunAtLoadIsFalse() {
        let task = ClaudeTask(name: "Test")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "test-task"
        let plist = service.buildPlist(task: task)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
    }

    func testPlistHasLogPaths() {
        let task = ClaudeTask(name: "Test")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "test-task"
        let plist = service.buildPlist(task: task)
        XCTAssertNotNil(plist["StandardOutPath"] as? String)
        XCTAssertNotNil(plist["StandardErrorPath"] as? String)
    }

    func testDailyPlistHasStartCalendarInterval() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 14, minute: 30))!
        let task = ClaudeTask(name: "Daily", schedule: schedule)
        task.sourceFolder = "/Users/me/project"
        task.taskId = "daily-task"
        let plist = service.buildPlist(task: task)
        let interval = plist["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?["Hour"], 14)
        XCTAssertEqual(interval?["Minute"], 30)
    }

    func testWeeklyPlistHasMultipleCalendarIntervals() {
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = [1, 4, 7] // Sun, Wed, Sat
        schedule.time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let task = ClaudeTask(name: "Weekly", schedule: schedule)
        task.sourceFolder = "/Users/me/project"
        task.taskId = "weekly-task"
        let plist = service.buildPlist(task: task)
        let intervals = plist["StartCalendarInterval"] as? [[String: Int]]
        XCTAssertNotNil(intervals)
        XCTAssertEqual(intervals?.count, 3)
        // launchd uses 0-based weekdays (0=Sunday), model uses 1-based
        let weekdays = intervals?.compactMap { $0["Weekday"] }.sorted()
        XCTAssertEqual(weekdays, [0, 3, 6])
    }

    func testIntervalPlistHasStartInterval() {
        var schedule = TaskSchedule()
        schedule.type = .interval
        schedule.intervalMinutes = 45
        let task = ClaudeTask(name: "Interval", schedule: schedule)
        task.sourceFolder = "/Users/me/project"
        task.taskId = "interval-task"
        let plist = service.buildPlist(task: task)
        XCTAssertEqual(plist["StartInterval"] as? Int, 45 * 60)
        XCTAssertNil(plist["StartCalendarInterval"])
    }

    func testMonthlyPlistHasStartCalendarInterval() {
        var schedule = TaskSchedule()
        schedule.type = .monthly
        schedule.time = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10, minute: 0))!
        let task = ClaudeTask(name: "Monthly", schedule: schedule)
        task.sourceFolder = "/Users/me/project"
        task.taskId = "monthly-task"
        let plist = service.buildPlist(task: task)
        let interval = plist["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?["Day"], 15)
        XCTAssertEqual(interval?["Hour"], 10)
        XCTAssertEqual(interval?["Minute"], 0)
    }

    func testManualPlistHasNoScheduleKeys() {
        var schedule = TaskSchedule()
        schedule.type = .manual
        let task = ClaudeTask(name: "Manual", schedule: schedule)
        task.sourceFolder = "/Users/me/project"
        task.taskId = "manual-task"
        let plist = service.buildPlist(task: task)
        XCTAssertNil(plist["StartCalendarInterval"])
        XCTAssertNil(plist["StartInterval"])
    }

    // MARK: - Composite key label tests

    func testPlistLabelFromCompositeKey() {
        let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "daily-cleanup"
        let label = service.plistLabel(for: task)
        XCTAssertTrue(label.hasPrefix("com.claudecron.task."))
        // Same inputs produce same label
        let label2 = service.plistLabel(for: task)
        XCTAssertEqual(label, label2)
    }

    func testPlistLabelUniqueness() {
        let task1 = ClaudeTask(name: "A", prompt: "x", directory: "/tmp")
        task1.sourceFolder = "/Users/me/project1"
        task1.taskId = "my-task"

        let task2 = ClaudeTask(name: "B", prompt: "y", directory: "/tmp")
        task2.sourceFolder = "/Users/me/project2"
        task2.taskId = "my-task"

        XCTAssertNotEqual(
            service.plistLabel(for: task1),
            service.plistLabel(for: task2)
        )
    }

    func testBuildPlistUsesCompositeKeyArgs() {
        let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
        task.sourceFolder = "/Users/me/project"
        task.taskId = "daily-cleanup"
        let plist = service.buildPlist(task: task)
        let args = plist["ProgramArguments"] as! [String]
        XCTAssertTrue(args.contains("--run-task"))
        XCTAssertTrue(args.contains("--source-folder"))
        XCTAssertTrue(args.contains(task.sourceFolder))
        XCTAssertTrue(args.contains("--task-id"))
        XCTAssertTrue(args.contains(task.taskId))
    }
}
