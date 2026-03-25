import XCTest
@testable import ClaudeCron

final class TaskRunTests: XCTestCase {

    func testInitSetsDefaults() {
        let task = ClaudeTask(name: "Test")
        let run = TaskRun(task: task)
        XCTAssertEqual(run.runStatus, .running)
        XCTAssertEqual(run.status, "Running")
        XCTAssertEqual(run.rawOutput, "")
        XCTAssertEqual(run.formattedOutput, "")
        XCTAssertNil(run.endedAt)
        XCTAssertNil(run.exitCode)
        XCTAssertNil(run.sessionId)
        XCTAssertNotNil(run.id)
    }

    func testRunStatusGetSet() {
        let task = ClaudeTask(name: "Test")
        let run = TaskRun(task: task)
        run.runStatus = .succeeded
        XCTAssertEqual(run.status, "Succeeded")
        XCTAssertEqual(run.runStatus, .succeeded)
        run.runStatus = .failed
        XCTAssertEqual(run.status, "Failed")
        XCTAssertEqual(run.runStatus, .failed)
        run.runStatus = .cancelled
        XCTAssertEqual(run.status, "Cancelled")
        XCTAssertEqual(run.runStatus, .cancelled)
    }

    func testRunStatusWithInvalidRawValue() {
        let task = ClaudeTask(name: "Test")
        let run = TaskRun(task: task)
        run.status = "InvalidStatus"
        XCTAssertEqual(run.runStatus, .failed)
    }

    func testDurationWhenRunning() {
        let task = ClaudeTask(name: "Test")
        let run = TaskRun(task: task)
        XCTAssertNil(run.duration)
    }

    func testDurationWhenCompleted() {
        let task = ClaudeTask(name: "Test")
        let run = TaskRun(task: task)
        run.endedAt = run.startedAt.addingTimeInterval(120)
        XCTAssertEqual(run.duration!, 120, accuracy: 0.1)
    }

    func testRunStatusRawValues() {
        XCTAssertEqual(RunStatus.running.rawValue, "Running")
        XCTAssertEqual(RunStatus.succeeded.rawValue, "Succeeded")
        XCTAssertEqual(RunStatus.failed.rawValue, "Failed")
        XCTAssertEqual(RunStatus.cancelled.rawValue, "Cancelled")
    }
}
