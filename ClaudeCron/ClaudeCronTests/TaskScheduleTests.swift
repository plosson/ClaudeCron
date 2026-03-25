import XCTest
@testable import ClaudeCron

final class TaskScheduleTests: XCTestCase {

    func testDefaultValues() {
        let schedule = TaskSchedule()
        XCTAssertEqual(schedule.type, .daily)
        XCTAssertTrue(schedule.weekdays.isEmpty)
        XCTAssertEqual(schedule.intervalMinutes, 60)
    }

    func testCodableRoundTrip() throws {
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = [1, 3, 5]
        schedule.intervalMinutes = 45
        schedule.time = Calendar.current.date(from: DateComponents(hour: 8, minute: 15))!
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(TaskSchedule.self, from: data)
        XCTAssertEqual(schedule, decoded)
    }

    func testCodableRoundTripAllTypes() throws {
        for type in ScheduleType.allCases {
            var schedule = TaskSchedule()
            schedule.type = type
            let data = try JSONEncoder().encode(schedule)
            let decoded = try JSONDecoder().decode(TaskSchedule.self, from: data)
            XCTAssertEqual(decoded.type, type)
        }
    }

    func testEqualSchedules() {
        let a = TaskSchedule()
        let b = TaskSchedule()
        XCTAssertEqual(a, b)
    }

    func testUnequalSchedules() {
        var a = TaskSchedule()
        var b = TaskSchedule()
        a.type = .daily
        b.type = .weekly
        XCTAssertNotEqual(a, b)
    }

    func testDisplaySummaryManual() {
        var schedule = TaskSchedule()
        schedule.type = .manual
        XCTAssertEqual(schedule.displaySummary, "Manual")
    }

    func testDisplaySummaryDaily() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 21, minute: 0))!
        XCTAssertTrue(schedule.displaySummary.hasPrefix("Daily at"))
    }

    func testDisplaySummaryWeekly() {
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = [2, 4]
        schedule.time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let summary = schedule.displaySummary
        XCTAssertTrue(summary.contains("Mon"))
        XCTAssertTrue(summary.contains("Wed"))
        XCTAssertTrue(summary.contains("at"))
    }

    func testDisplaySummaryMonthly() {
        var schedule = TaskSchedule()
        schedule.type = .monthly
        schedule.time = Calendar.current.date(from: DateComponents(day: 15, hour: 14, minute: 0))!
        let summary = schedule.displaySummary
        XCTAssertTrue(summary.contains("Monthly"))
        XCTAssertTrue(summary.contains("15"))
    }

    func testDisplaySummaryIntervalMinutes() {
        var schedule = TaskSchedule()
        schedule.type = .interval
        schedule.intervalMinutes = 30
        XCTAssertEqual(schedule.displaySummary, "Every 30 min")
    }

    func testDisplaySummaryIntervalHours() {
        var schedule = TaskSchedule()
        schedule.type = .interval
        schedule.intervalMinutes = 120
        XCTAssertEqual(schedule.displaySummary, "Every 2 hr")
    }
}
