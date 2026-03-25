import XCTest
@testable import ClaudeCron

final class LaunchdServiceTests: XCTestCase {

    private let service = LaunchdService.shared
    private let testLabel = "com.claudecron.task.test"

    func testPlistContainsLabel() {
        let task = ClaudeTask(name: "Test")
        let plist = service.buildPlist(task: task, label: testLabel)
        XCTAssertEqual(plist["Label"] as? String, testLabel)
    }

    func testPlistContainsProgramArguments() {
        let task = ClaudeTask(name: "Test")
        let plist = service.buildPlist(task: task, label: testLabel)
        let args = plist["ProgramArguments"] as? [String]
        XCTAssertNotNil(args)
        XCTAssertTrue(args!.contains("--run-task"))
        XCTAssertTrue(args!.contains(task.id.uuidString))
    }

    func testPlistRunAtLoadIsFalse() {
        let task = ClaudeTask(name: "Test")
        let plist = service.buildPlist(task: task, label: testLabel)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
    }

    func testPlistHasLogPaths() {
        let task = ClaudeTask(name: "Test")
        let plist = service.buildPlist(task: task, label: testLabel)
        XCTAssertNotNil(plist["StandardOutPath"] as? String)
        XCTAssertNotNil(plist["StandardErrorPath"] as? String)
    }

    func testDailyPlistHasStartCalendarInterval() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 14, minute: 30))!
        let task = ClaudeTask(name: "Daily", schedule: schedule)
        let plist = service.buildPlist(task: task, label: testLabel)
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
        let plist = service.buildPlist(task: task, label: testLabel)
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
        let plist = service.buildPlist(task: task, label: testLabel)
        XCTAssertEqual(plist["StartInterval"] as? Int, 45 * 60)
        XCTAssertNil(plist["StartCalendarInterval"])
    }

    func testMonthlyPlistHasStartCalendarInterval() {
        var schedule = TaskSchedule()
        schedule.type = .monthly
        schedule.time = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10, minute: 0))!
        let task = ClaudeTask(name: "Monthly", schedule: schedule)
        let plist = service.buildPlist(task: task, label: testLabel)
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
        let plist = service.buildPlist(task: task, label: testLabel)
        XCTAssertNil(plist["StartCalendarInterval"])
        XCTAssertNil(plist["StartInterval"])
    }
}
