import XCTest
@testable import ClaudeCron

final class TaskDefinitionTests: XCTestCase {

    func testDecodeMinimalTask() throws {
        let json = """
        {
          "tasks": {
            "my-task": {
              "name": "My Task",
              "prompt": "do something",
              "model": "sonnet",
              "schedule": { "type": "Manual" }
            }
          }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(SettingsFile.self, from: json)
        XCTAssertEqual(file.tasks.count, 1)
        let task = file.tasks["my-task"]
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.name, "My Task")
        XCTAssertEqual(task?.prompt, "do something")
        XCTAssertEqual(task?.model, "sonnet")
        XCTAssertNil(task?.path)
        XCTAssertEqual(task?.schedule.type, "Manual")
    }

    func testDecodeFullTask() throws {
        let json = """
        {
          "tasks": {
            "daily-cleanup": {
              "name": "Daily Cleanup",
              "prompt": "clean up",
              "path": "/Users/me/project",
              "model": "opus",
              "permissionMode": "bypassPermissions",
              "schedule": {
                "type": "Weekly",
                "hour": 14,
                "minute": 30,
                "weekdays": [2, 4, 6]
              },
              "isEnabled": false,
              "sessionMode": "Resume Session",
              "sessionId": "abc-123",
              "allowedTools": ["Read", "Write"],
              "disallowedTools": ["Bash"],
              "notifyOnStart": true,
              "notifyOnEnd": false
            }
          }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(SettingsFile.self, from: json)
        let task = try XCTUnwrap(file.tasks["daily-cleanup"])
        XCTAssertEqual(task.path, "/Users/me/project")
        XCTAssertEqual(task.model, "opus")
        XCTAssertEqual(task.permissionMode, "bypassPermissions")
        XCTAssertEqual(task.schedule.type, "Weekly")
        XCTAssertEqual(task.schedule.hour, 14)
        XCTAssertEqual(task.schedule.minute, 30)
        XCTAssertEqual(task.schedule.weekdays, [2, 4, 6])
        XCTAssertEqual(task.isEnabled, false)
        XCTAssertEqual(task.sessionMode, "Resume Session")
        XCTAssertEqual(task.sessionId, "abc-123")
        XCTAssertEqual(task.allowedTools, ["Read", "Write"])
        XCTAssertEqual(task.disallowedTools, ["Bash"])
        XCTAssertTrue(task.notifyOnStart)
        XCTAssertFalse(task.notifyOnEnd)
    }

    func testEncodeRoundTrip() throws {
        var file = SettingsFile()
        var task = TaskDefinition(name: "Test", prompt: "hello")
        task.model = "haiku"
        task.schedule = ScheduleDefinition(type: "Interval", intervalMinutes: 45)
        file.tasks["test-task"] = task

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SettingsFile.self, from: data)
        let t = try XCTUnwrap(decoded.tasks["test-task"])
        XCTAssertEqual(t.name, "Test")
        XCTAssertEqual(t.prompt, "hello")
        XCTAssertEqual(t.model, "haiku")
        XCTAssertEqual(t.schedule.type, "Interval")
        XCTAssertEqual(t.schedule.intervalMinutes, 45)
    }

    func testDefaultValues() {
        let task = TaskDefinition(name: "X", prompt: "Y")
        XCTAssertEqual(task.model, "sonnet")
        XCTAssertEqual(task.permissionMode, "default")
        XCTAssertTrue(task.isEnabled)
        XCTAssertEqual(task.sessionMode, "New Session")
        XCTAssertNil(task.sessionId)
        XCTAssertTrue(task.allowedTools.isEmpty)
        XCTAssertTrue(task.disallowedTools.isEmpty)
        XCTAssertFalse(task.notifyOnStart)
        XCTAssertTrue(task.notifyOnEnd)
    }

    func testScheduleDefinitionDefaults() {
        let s = ScheduleDefinition(type: "Daily")
        XCTAssertNil(s.hour)
        XCTAssertNil(s.minute)
        XCTAssertNil(s.day)
        XCTAssertNil(s.weekdays)
        XCTAssertNil(s.intervalMinutes)
    }

    func testConvertScheduleDefinitionToTaskSchedule() {
        let def = ScheduleDefinition(type: "Weekly", hour: 10, minute: 15, weekdays: [1, 3, 5])
        let schedule = def.toTaskSchedule()
        XCTAssertEqual(schedule.type, .weekly)
        XCTAssertEqual(schedule.weekdays, [1, 3, 5])
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: schedule.time), 10)
        XCTAssertEqual(cal.component(.minute, from: schedule.time), 15)
    }

    func testConvertTaskScheduleToScheduleDefinition() {
        var schedule = TaskSchedule()
        schedule.type = .monthly
        schedule.time = Calendar.current.date(from: DateComponents(day: 15, hour: 14, minute: 30))!
        schedule.weekdays = []
        let def = ScheduleDefinition.from(schedule)
        XCTAssertEqual(def.type, "Monthly")
        XCTAssertEqual(def.hour, 14)
        XCTAssertEqual(def.minute, 30)
        XCTAssertEqual(def.day, 15)
    }
}
