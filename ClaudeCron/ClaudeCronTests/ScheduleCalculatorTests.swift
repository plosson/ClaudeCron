import XCTest
@testable import ClaudeCron

final class ScheduleCalculatorTests: XCTestCase {

    // MARK: - Daily

    func testDailyReturnsCorrectCount() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 10, minute: 30))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 5)
        XCTAssertEqual(runs.count, 5)
    }

    func testDailyRunsAreOneDayApart() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 10, minute: 30))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 3)
        guard runs.count >= 3 else { return XCTFail("Expected at least 3 runs") }
        let calendar = Calendar.current
        for i in 1..<runs.count {
            let diff = calendar.dateComponents([.day], from: runs[i - 1], to: runs[i])
            XCTAssertEqual(diff.day, 1, "Daily runs should be 1 day apart")
        }
    }

    func testDailyRunsAreInTheFuture() {
        var schedule = TaskSchedule()
        schedule.type = .daily
        schedule.time = Calendar.current.date(from: DateComponents(hour: 10, minute: 30))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 3)
        for run in runs {
            XCTAssertGreaterThan(run, Date(), "All runs should be in the future")
        }
    }

    // MARK: - Weekly

    func testWeeklyOnlyIncludesSelectedDays() {
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = [2, 4, 6]
        schedule.time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 5)
        let calendar = Calendar.current
        for run in runs {
            let weekday = calendar.component(.weekday, from: run)
            XCTAssertTrue([2, 4, 6].contains(weekday), "Weekday \(weekday) should be in [2, 4, 6]")
        }
    }

    func testWeeklyWithNoWeekdaysReturnsEmpty() {
        var schedule = TaskSchedule()
        schedule.type = .weekly
        schedule.weekdays = []
        schedule.time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 5)
        XCTAssertTrue(runs.isEmpty, "No weekdays selected should yield no runs")
    }

    // MARK: - Interval

    func testIntervalRunsAreCorrectlySpaced() {
        var schedule = TaskSchedule()
        schedule.type = .interval
        schedule.intervalMinutes = 30
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 4)
        XCTAssertEqual(runs.count, 4)
        for i in 1..<runs.count {
            let diff = runs[i].timeIntervalSince(runs[i - 1])
            XCTAssertEqual(diff, 30 * 60, accuracy: 1.0, "Interval runs should be 30 minutes apart")
        }
    }

    // MARK: - Monthly

    func testMonthlyRunsAreOneMonthApart() {
        var schedule = TaskSchedule()
        schedule.type = .monthly
        schedule.time = Calendar.current.date(from: DateComponents(month: 1, day: 15, hour: 14, minute: 0))!
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 3)
        let calendar = Calendar.current
        for run in runs {
            let day = calendar.component(.day, from: run)
            XCTAssertEqual(day, 15, "Monthly runs should fall on day 15")
        }
        guard runs.count >= 2 else { return }
        for i in 1..<runs.count {
            let diff = calendar.dateComponents([.month], from: runs[i - 1], to: runs[i])
            XCTAssertEqual(diff.month, 1, "Monthly runs should be 1 month apart")
        }
    }

    // MARK: - Manual

    func testManualReturnsEmpty() {
        var schedule = TaskSchedule()
        schedule.type = .manual
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 5)
        XCTAssertTrue(runs.isEmpty, "Manual schedule should return no upcoming runs")
    }

    // MARK: - Count parameter

    func testCustomCountIsRespected() {
        var schedule = TaskSchedule()
        schedule.type = .interval
        schedule.intervalMinutes = 60
        let runs = ScheduleCalculator.nextRuns(for: schedule, count: 10)
        XCTAssertEqual(runs.count, 10)
    }
}
