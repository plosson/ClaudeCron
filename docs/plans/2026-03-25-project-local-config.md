# Project-Local Config (.ccron/settings.json) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move task definitions from SwiftData to `.ccron/settings.json` files that live inside project folders (or `~/.ccron/settings.json` for global tasks), making task config portable and version-controllable.

**Architecture:** JSON files are the source of truth for task definitions. SwiftData remains for run history only. A `ConfigService` reads/writes `.ccron/settings.json` files. `ClaudeTask` gains `sourceFolder` and `taskId` (string key) properties. The app maintains a list of registered folders in UserDefaults. Task identity = `sourceFolder + taskId`. Launchd labels derive from a stable hash of this identity.

**Tech Stack:** Swift, SwiftUI, SwiftData (runs only), Foundation (JSONEncoder/Decoder, FileManager), UserDefaults (registered folders)

---

## JSON Format

**`~/.ccron/settings.json` (global):**
```json
{
  "tasks": {
    "daily-cleanup": {
      "name": "Daily Cleanup",
      "prompt": "Clean up temp files",
      "path": "/Users/me/projects/myapp",
      "model": "sonnet",
      "permissionMode": "default",
      "schedule": {
        "type": "daily",
        "hour": 9,
        "minute": 30
      },
      "isEnabled": true,
      "sessionMode": "new",
      "allowedTools": ["Read", "Write"],
      "disallowedTools": [],
      "notifyOnStart": false,
      "notifyOnEnd": true
    }
  }
}
```

**`/project/.ccron/settings.json` (project-local):**
```json
{
  "tasks": {
    "run-tests": {
      "name": "Nightly Tests",
      "prompt": "Run the test suite and report failures",
      "model": "sonnet",
      "permissionMode": "acceptEdits",
      "schedule": {
        "type": "daily",
        "hour": 22,
        "minute": 0
      },
      "isEnabled": true,
      "sessionMode": "new",
      "allowedTools": [],
      "disallowedTools": [],
      "notifyOnStart": false,
      "notifyOnEnd": true
    }
  }
}
```

Note: `path` is **required** for global tasks, **omitted** for project-local tasks (defaults to the project folder).

### Schedule format in JSON

Instead of storing a `Date` object (which is not portable), the JSON uses explicit fields:

| Schedule type | Fields |
|---|---|
| `manual` | `{ "type": "manual" }` |
| `daily` | `{ "type": "daily", "hour": 9, "minute": 30 }` |
| `weekly` | `{ "type": "weekly", "hour": 9, "minute": 30, "weekdays": [2, 4, 6] }` |
| `monthly` | `{ "type": "monthly", "day": 15, "hour": 14, "minute": 0 }` |
| `interval` | `{ "type": "interval", "intervalMinutes": 60 }` |

---

## Task Overview

| Task | Description | Files |
|------|-------------|-------|
| 1 | JSON config model (`TaskDefinition`, `ScheduleDefinition`, `SettingsFile`) | New: `Models/TaskDefinition.swift`, Test: `TaskDefinitionTests.swift` |
| 2 | `ConfigService` — read/write `.ccron/settings.json` | New: `Services/ConfigService.swift`, Test: `ConfigServiceTests.swift` |
| 3 | Add `sourceFolder` + `taskId` to `ClaudeTask`, conversion helpers | Modify: `Models/ClaudeTask.swift`, Test: `ClaudeTaskTests.swift` |
| 4 | Update `LaunchdService` for string-based task identity | Modify: `Services/LaunchdService.swift`, Test: `LaunchdServiceTests.swift` |
| 5 | Folder registration (UserDefaults) | New: `Services/FolderRegistry.swift`, Test: `FolderRegistryTests.swift` |
| 6 | Wire "Add Folder" + import flow in `ContentView` | Modify: `Views/ContentView.swift`, `Views/TaskListView.swift` |
| 7 | Write-back: CRUD operations persist to JSON | Modify: `Views/ContentView.swift`, `Views/TaskDetailView.swift` |
| 8 | Resync + Remove Folder | Modify: `Views/ContentView.swift`, `Views/TaskListView.swift` |
| 9 | Update headless run mode for new task identity | Modify: `ClaudeCronApp.swift` |
| 10 | Integration test: full round-trip | Test: `ConfigIntegrationTests.swift` |

---

### Task 1: JSON Config Model

Create `Codable` structs that represent the `.ccron/settings.json` format, independent of SwiftData.

**Files:**
- Create: `ClaudeCron/ClaudeCron/Models/TaskDefinition.swift`
- Test: `ClaudeCron/ClaudeCronTests/TaskDefinitionTests.swift`

**Step 1: Write the failing test**

```swift
// ClaudeCron/ClaudeCronTests/TaskDefinitionTests.swift
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
              "schedule": { "type": "manual" }
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
        XCTAssertEqual(task?.schedule.type, "manual")
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
                "type": "weekly",
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
        XCTAssertEqual(task.schedule.type, "weekly")
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
        task.schedule = ScheduleDefinition(type: "interval", intervalMinutes: 45)
        file.tasks["test-task"] = task

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SettingsFile.self, from: data)
        let t = try XCTUnwrap(decoded.tasks["test-task"])
        XCTAssertEqual(t.name, "Test")
        XCTAssertEqual(t.prompt, "hello")
        XCTAssertEqual(t.model, "haiku")
        XCTAssertEqual(t.schedule.type, "interval")
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
        let s = ScheduleDefinition(type: "daily")
        XCTAssertNil(s.hour)
        XCTAssertNil(s.minute)
        XCTAssertNil(s.day)
        XCTAssertNil(s.weekdays)
        XCTAssertNil(s.intervalMinutes)
    }

    func testConvertScheduleDefinitionToTaskSchedule() {
        let def = ScheduleDefinition(type: "weekly", hour: 10, minute: 15, weekdays: [1, 3, 5])
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
        schedule.time = Calendar.current.date(from: DateComponents(hour: 14, minute: 30, day: 15))!
        schedule.weekdays = []
        let def = ScheduleDefinition.from(schedule)
        XCTAssertEqual(def.type, "Monthly")
        XCTAssertEqual(def.hour, 14)
        XCTAssertEqual(def.minute, 30)
        XCTAssertEqual(def.day, 15)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/TaskDefinitionTests 2>&1 | tail -20`
Expected: FAIL — `SettingsFile`, `TaskDefinition`, `ScheduleDefinition` not defined

**Step 3: Write minimal implementation**

```swift
// ClaudeCron/ClaudeCron/Models/TaskDefinition.swift
import Foundation

/// Represents a .ccron/settings.json file
struct SettingsFile: Codable {
    var tasks: [String: TaskDefinition] = [:]
}

/// A single task definition as stored in JSON — independent of SwiftData
struct TaskDefinition: Codable {
    var name: String
    var prompt: String
    var path: String?                   // Required for global tasks, nil for project-local
    var model: String = "sonnet"
    var permissionMode: String = "default"
    var schedule: ScheduleDefinition = ScheduleDefinition(type: "Manual")
    var isEnabled: Bool = true
    var sessionMode: String = "New Session"
    var sessionId: String?
    var allowedTools: [String] = []
    var disallowedTools: [String] = []
    var notifyOnStart: Bool = false
    var notifyOnEnd: Bool = true
}

/// Schedule as stored in JSON — uses explicit hour/minute/day instead of Date
struct ScheduleDefinition: Codable, Equatable {
    var type: String                    // "Manual", "Daily", "Weekly", "Monthly", "Interval"
    var hour: Int?
    var minute: Int?
    var day: Int?                       // For monthly (1-31)
    var weekdays: [Int]?                // For weekly (1=Sun, 7=Sat)
    var intervalMinutes: Int?           // For interval

    /// Convert to the app's internal TaskSchedule
    func toTaskSchedule() -> TaskSchedule {
        var schedule = TaskSchedule()
        schedule.type = ScheduleType(rawValue: type) ?? .manual

        if let hour = hour, let minute = minute {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let day = day {
                components.day = day
            }
            schedule.time = Calendar.current.date(from: components) ?? Date()
        }

        if let weekdays = weekdays {
            schedule.weekdays = Set(weekdays)
        }

        if let intervalMinutes = intervalMinutes {
            schedule.intervalMinutes = intervalMinutes
        }

        return schedule
    }

    /// Create from the app's internal TaskSchedule
    static func from(_ schedule: TaskSchedule) -> ScheduleDefinition {
        let cal = Calendar.current
        var def = ScheduleDefinition(type: schedule.type.rawValue)

        switch schedule.type {
        case .daily:
            def.hour = cal.component(.hour, from: schedule.time)
            def.minute = cal.component(.minute, from: schedule.time)
        case .weekly:
            def.hour = cal.component(.hour, from: schedule.time)
            def.minute = cal.component(.minute, from: schedule.time)
            def.weekdays = schedule.weekdays.sorted()
        case .monthly:
            def.hour = cal.component(.hour, from: schedule.time)
            def.minute = cal.component(.minute, from: schedule.time)
            def.day = cal.component(.day, from: schedule.time)
        case .interval:
            def.intervalMinutes = schedule.intervalMinutes
        case .manual:
            break
        }

        return def
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/TaskDefinitionTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add ClaudeCron/ClaudeCron/Models/TaskDefinition.swift ClaudeCron/ClaudeCronTests/TaskDefinitionTests.swift
git commit -m "feat: add TaskDefinition and SettingsFile Codable models for .ccron/settings.json"
```

---

### Task 2: ConfigService — Read/Write .ccron/settings.json

A service that reads and writes `.ccron/settings.json` files from disk.

**Files:**
- Create: `ClaudeCron/ClaudeCron/Services/ConfigService.swift`
- Test: `ClaudeCron/ClaudeCronTests/ConfigServiceTests.swift`

**Step 1: Write the failing test**

```swift
// ClaudeCron/ClaudeCronTests/ConfigServiceTests.swift
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
        // Pretty-printed JSON should contain newlines and indentation
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/ConfigServiceTests 2>&1 | tail -20`
Expected: FAIL — `ConfigService` not defined

**Step 3: Write minimal implementation**

```swift
// ClaudeCron/ClaudeCron/Services/ConfigService.swift
import Foundation

final class ConfigService {
    static let shared = ConfigService()

    private let fileName = ".ccron/settings.json"

    func settingsFilePath(for folder: String) -> String {
        (folder as NSString).appendingPathComponent(fileName)
    }

    /// Read a .ccron/settings.json from a folder. Returns empty SettingsFile if not found or corrupt.
    func read(folder: String) -> SettingsFile {
        let path = settingsFilePath(for: folder)
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return SettingsFile()
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(SettingsFile.self, from: data)) ?? SettingsFile()
    }

    /// Write a SettingsFile to a folder's .ccron/settings.json. Creates .ccron/ directory if needed.
    func write(_ file: SettingsFile, to folder: String) throws {
        let dirPath = (folder as NSString).appendingPathComponent(".ccron")
        try FileManager.default.createDirectory(
            atPath: dirPath, withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let path = settingsFilePath(for: folder)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/ConfigServiceTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add ClaudeCron/ClaudeCron/Services/ConfigService.swift ClaudeCron/ClaudeCronTests/ConfigServiceTests.swift
git commit -m "feat: add ConfigService for reading/writing .ccron/settings.json files"
```

---

### Task 3: Add sourceFolder + taskId to ClaudeTask

Add properties to `ClaudeTask` so each task knows where it came from and what its string key is.

**Files:**
- Modify: `ClaudeCron/ClaudeCron/Models/ClaudeTask.swift`
- Modify: `ClaudeCron/ClaudeCronTests/ClaudeTaskTests.swift`

**Step 1: Write the failing tests**

Add to `ClaudeTaskTests.swift`:

```swift
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
    task.sourceFolder = NSHomeDirectory()  // global task

    let def = task.toTaskDefinition(isGlobal: true)
    XCTAssertEqual(def.name, "Test")
    XCTAssertEqual(def.prompt, "do it")
    XCTAssertEqual(def.path, "/tmp")  // global tasks include path
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
    XCTAssertNil(def.path)  // project-local tasks omit path
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/ClaudeTaskTests 2>&1 | tail -20`
Expected: FAIL — `sourceFolder`, `taskId`, `compositeKey`, `toTaskDefinition`, `update(from:)` not defined

**Step 3: Add properties and methods to ClaudeTask**

Add these properties to `ClaudeTask` (after `createdAt`):

```swift
var sourceFolder: String = ""   // folder that owns this task's settings.json
var taskId: String = ""         // string key in the tasks dict (e.g. "daily-cleanup")

/// Unique identity across all settings files
var compositeKey: String {
    "\(sourceFolder)::\(taskId)"
}

/// Convert to a TaskDefinition for JSON serialization
func toTaskDefinition(isGlobal: Bool) -> TaskDefinition {
    let schedule = self.schedule
    var def = TaskDefinition(name: name, prompt: prompt)
    if isGlobal {
        def.path = directory
    }
    def.model = model
    def.permissionMode = permissionMode
    def.schedule = ScheduleDefinition.from(schedule)
    def.isEnabled = isEnabled
    def.sessionMode = sessionMode
    def.sessionId = sessionId
    def.allowedTools = allowedTools.split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    def.disallowedTools = disallowedTools.split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    def.notifyOnStart = notifyOnStart
    def.notifyOnEnd = notifyOnEnd
    return def
}

/// Update this task's properties from a TaskDefinition
func update(from def: TaskDefinition, resolvedPath: String) {
    name = def.name
    prompt = def.prompt
    directory = resolvedPath
    model = def.model
    permissionMode = def.permissionMode
    schedule = def.schedule.toTaskSchedule()
    isEnabled = def.isEnabled
    sessionMode = def.sessionMode
    sessionId = def.sessionId
    allowedTools = def.allowedTools.joined(separator: ",")
    disallowedTools = def.disallowedTools.joined(separator: ",")
    notifyOnStart = def.notifyOnStart
    notifyOnEnd = def.notifyOnEnd
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/ClaudeTaskTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add ClaudeCron/ClaudeCron/Models/ClaudeTask.swift ClaudeCron/ClaudeCronTests/ClaudeTaskTests.swift
git commit -m "feat: add sourceFolder, taskId, and conversion helpers to ClaudeTask"
```

---

### Task 4: Update LaunchdService for String-Based Task Identity

Change launchd labels from UUID-based to composite-key-based (using a short hash of `sourceFolder::taskId`).

**Files:**
- Modify: `ClaudeCron/ClaudeCron/Services/LaunchdService.swift`
- Modify: `ClaudeCron/ClaudeCronTests/LaunchdServiceTests.swift`

**Step 1: Write failing tests**

Add to `LaunchdServiceTests.swift`:

```swift
func testPlistLabelFromCompositeKey() {
    let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
    task.sourceFolder = "/Users/me/project"
    task.taskId = "daily-cleanup"
    let label = LaunchdService.shared.plistLabel(for: task)
    // Label should be deterministic and start with prefix
    XCTAssertTrue(label.hasPrefix("com.claudecron.task."))
    // Same inputs should produce same label
    let label2 = LaunchdService.shared.plistLabel(for: task)
    XCTAssertEqual(label, label2)
}

func testPlistLabelUniqueness() {
    let task1 = ClaudeTask(name: "A", prompt: "x", directory: "/tmp")
    task1.sourceFolder = "/Users/me/project1"
    task1.taskId = "my-task"

    let task2 = ClaudeTask(name: "B", prompt: "y", directory: "/tmp")
    task2.sourceFolder = "/Users/me/project2"
    task2.taskId = "my-task"

    let label1 = LaunchdService.shared.plistLabel(for: task1)
    let label2 = LaunchdService.shared.plistLabel(for: task2)
    XCTAssertNotEqual(label1, label2)
}

func testBuildPlistUsesCompositeKeyArgs() {
    let task = ClaudeTask(name: "Test", prompt: "hello", directory: "/tmp")
    task.sourceFolder = "/Users/me/project"
    task.taskId = "daily-cleanup"
    let label = LaunchdService.shared.plistLabel(for: task)
    let plist = LaunchdService.shared.buildPlist(task: task, label: label)
    let args = plist["ProgramArguments"] as! [String]
    // Should pass --source-folder and --task-id instead of UUID
    XCTAssertTrue(args.contains("--run-task"))
    XCTAssertTrue(args.contains("--source-folder"))
    XCTAssertTrue(args.contains(task.sourceFolder))
    XCTAssertTrue(args.contains("--task-id"))
    XCTAssertTrue(args.contains(task.taskId))
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/LaunchdServiceTests 2>&1 | tail -20`
Expected: FAIL

**Step 3: Update LaunchdService**

Key changes to `LaunchdService.swift`:

1. Add a new `plistLabel(for task: ClaudeTask)` method that hashes the composite key:

```swift
import CryptoKit

func plistLabel(for task: ClaudeTask) -> String {
    let key = task.compositeKey
    let hash = Insecure.MD5.hash(data: Data(key.utf8))
    let short = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    return "\(plistPrefix)\(short)"
}
```

2. Add matching `plistPath(for task: ClaudeTask)` helper.

3. Update `install(task:)` to use `plistLabel(for: task)` and `plistPath(for: task)`.

4. Update `uninstall(task:)` to accept `ClaudeTask` instead of `UUID`.

5. Update `buildPlist` to pass `--run-task --source-folder <folder> --task-id <id>` instead of `--run-task <UUID>`:

```swift
"ProgramArguments": [appPath, "--run-task", "--source-folder", task.sourceFolder, "--task-id", task.taskId]
```

6. Keep the old `uninstall(taskId: UUID)` temporarily for backward compatibility but mark as deprecated.

**Step 4: Run tests**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/LaunchdServiceTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Run full test suite to check nothing broke**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests PASS (old tests may need updating for new signature)

**Step 6: Commit**

```bash
git add ClaudeCron/ClaudeCron/Services/LaunchdService.swift ClaudeCron/ClaudeCronTests/LaunchdServiceTests.swift
git commit -m "feat: update LaunchdService to use composite key (sourceFolder+taskId) for labels"
```

---

### Task 5: Folder Registration

A small service to track which folders are registered with the app. Uses UserDefaults.

**Files:**
- Create: `ClaudeCron/ClaudeCron/Services/FolderRegistry.swift`
- Test: `ClaudeCron/ClaudeCronTests/FolderRegistryTests.swift`

**Step 1: Write the failing test**

```swift
// ClaudeCron/ClaudeCronTests/FolderRegistryTests.swift
import XCTest
@testable import ClaudeCron

final class FolderRegistryTests: XCTestCase {
    var registry: FolderRegistry!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ccron-test-\(UUID().uuidString)")!
        registry = FolderRegistry(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.suiteName ?? "")
        super.tearDown()
    }

    func testInitiallyEmpty() {
        XCTAssertTrue(registry.folders.isEmpty)
    }

    func testAddFolder() {
        registry.add("/Users/me/project")
        XCTAssertEqual(registry.folders, ["/Users/me/project"])
    }

    func testAddDuplicateFolder() {
        registry.add("/Users/me/project")
        registry.add("/Users/me/project")
        XCTAssertEqual(registry.folders.count, 1)
    }

    func testRemoveFolder() {
        registry.add("/Users/me/project")
        registry.remove("/Users/me/project")
        XCTAssertTrue(registry.folders.isEmpty)
    }

    func testPersistence() {
        registry.add("/Users/me/project")
        // Create a new instance with the same UserDefaults
        let registry2 = FolderRegistry(defaults: defaults)
        XCTAssertEqual(registry2.folders, ["/Users/me/project"])
    }

    func testHomeAlwaysIncluded() {
        // The global folder (~) should always be present
        XCTAssertTrue(registry.allFolders.contains(NSHomeDirectory()))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/FolderRegistryTests 2>&1 | tail -20`
Expected: FAIL — `FolderRegistry` not defined

**Step 3: Write minimal implementation**

```swift
// ClaudeCron/ClaudeCron/Services/FolderRegistry.swift
import Foundation

@Observable
final class FolderRegistry {
    private let defaults: UserDefaults
    private let key = "registeredFolders"

    private(set) var folders: [String] = []

    /// All folders including the implicit global (~) folder
    var allFolders: [String] {
        let home = NSHomeDirectory()
        if folders.contains(home) {
            return folders
        }
        return [home] + folders
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.folders = defaults.stringArray(forKey: key) ?? []
    }

    func add(_ folder: String) {
        guard !folders.contains(folder) else { return }
        folders.append(folder)
        save()
    }

    func remove(_ folder: String) {
        folders.removeAll { $0 == folder }
        save()
    }

    private func save() {
        defaults.set(folders, forKey: key)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/FolderRegistryTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add ClaudeCron/ClaudeCron/Services/FolderRegistry.swift ClaudeCron/ClaudeCronTests/FolderRegistryTests.swift
git commit -m "feat: add FolderRegistry to track registered project folders"
```

---

### Task 6: Wire "Add Folder" + Import Flow

Add UI for adding a folder and importing its tasks from `.ccron/settings.json`.

**Files:**
- Modify: `ClaudeCron/ClaudeCron/Views/TaskListView.swift`
- Modify: `ClaudeCron/ClaudeCron/Views/ContentView.swift`
- Modify: `ClaudeCron/ClaudeCron/ClaudeCronApp.swift` (inject FolderRegistry)

**Step 1: Update ClaudeCronApp to create and inject FolderRegistry**

In `ClaudeCronApp.swift`, add:

```swift
@State private var folderRegistry = FolderRegistry()
```

Pass it to ContentView and MenuBarView via `.environment()`:

```swift
ContentView()
    .environment(folderRegistry)
```

**Step 2: Add "Add Folder" button to TaskListView**

In the bottom `safeAreaInset`, next to the Settings gear, add a folder+ button:

```swift
Button(action: { onAddFolder() }) {
    Label("Add Folder", systemImage: "folder.badge.plus")
}
.buttonStyle(.plain)
.foregroundStyle(.secondary)
```

Add a new binding: `var onAddFolder: () -> Void`

**Step 3: Add import logic in ContentView**

Add a method `importFolder(_ folderPath: String)` to ContentView:

```swift
private func importFolder(_ folderPath: String) {
    let registry: FolderRegistry = // from environment
    let config = ConfigService.shared
    let isGlobal = folderPath == NSHomeDirectory()

    registry.add(folderPath)
    let settings = config.read(folder: folderPath)

    for (taskId, definition) in settings.tasks {
        let resolvedPath = isGlobal ? (definition.path ?? folderPath) : folderPath
        let compositeKey = "\(folderPath)::\(taskId)"

        // Check if task already exists
        let descriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { $0.sourceFolder == folderPath && $0.taskId == taskId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: definition, resolvedPath: resolvedPath)
        } else {
            let task = ClaudeTask()
            task.taskId = taskId
            task.sourceFolder = folderPath
            task.update(from: definition, resolvedPath: resolvedPath)
            modelContext.insert(task)
        }
    }

    try? modelContext.save()

    // Install launchd jobs for imported tasks
    let allDescriptor = FetchDescriptor<ClaudeTask>(
        predicate: #Predicate { $0.sourceFolder == folderPath }
    )
    if let tasks = try? modelContext.fetch(allDescriptor) {
        for task in tasks {
            LaunchdService.shared.install(task: task)
        }
    }
}
```

Wire the "Add Folder" button to show `NSOpenPanel` and call `importFolder`.

**Step 4: Verify manually**

- Build and run the app
- Click "Add Folder", select a folder with a `.ccron/settings.json`
- Verify tasks appear in the sidebar

**Step 5: Commit**

```bash
git add ClaudeCron/ClaudeCron/Views/ContentView.swift ClaudeCron/ClaudeCron/Views/TaskListView.swift ClaudeCron/ClaudeCron/ClaudeCronApp.swift
git commit -m "feat: add folder import UI — 'Add Folder' reads .ccron/settings.json and creates tasks"
```

---

### Task 7: Write-Back — CRUD Operations Persist to JSON

When creating, editing, or deleting tasks in the UI, write changes back to the source `.ccron/settings.json`.

**Files:**
- Modify: `ClaudeCron/ClaudeCron/Views/ContentView.swift`
- Modify: `ClaudeCron/ClaudeCron/Views/TaskDetailView.swift`

**Step 1: Create a helper method for writing back**

Add to ContentView (or a shared location):

```swift
private func persistToJSON(task: ClaudeTask) {
    let folder = task.sourceFolder
    guard !folder.isEmpty else { return }
    let isGlobal = folder == NSHomeDirectory()
    var settings = ConfigService.shared.read(folder: folder)
    settings.tasks[task.taskId] = task.toTaskDefinition(isGlobal: isGlobal)
    try? ConfigService.shared.write(settings, to: folder)
}

private func removeFromJSON(task: ClaudeTask) {
    let folder = task.sourceFolder
    guard !folder.isEmpty else { return }
    var settings = ConfigService.shared.read(folder: folder)
    settings.tasks.removeValue(forKey: task.taskId)
    try? ConfigService.shared.write(settings, to: folder)
}
```

**Step 2: Update the onSave closure in ContentView**

After `modelContext.save()` and `LaunchdService.shared.install(task:)`, add:

```swift
persistToJSON(task: task)
```

For new tasks: before inserting, prompt for a task ID (or auto-generate from name as slug). Set `task.taskId` and `task.sourceFolder` (let user choose global vs a registered folder).

**Step 3: Update deleteTask in TaskDetailView**

After `LaunchdService.shared.uninstall(...)` and `modelContext.delete(task)`, call back to ContentView to remove from JSON. This can be done via an `onDelete` closure passed to TaskDetailView.

**Step 4: Update toggleEnabled in TaskDetailView**

After toggling and saving, call `persistToJSON`.

**Step 5: Verify manually**

- Edit a task in the UI → check `.ccron/settings.json` updated
- Delete a task → check it's removed from JSON
- Toggle enabled → check `isEnabled` updated in JSON

**Step 6: Commit**

```bash
git add ClaudeCron/ClaudeCron/Views/ContentView.swift ClaudeCron/ClaudeCron/Views/TaskDetailView.swift
git commit -m "feat: write-back — task CRUD persists changes to .ccron/settings.json"
```

---

### Task 8: Resync + Remove Folder

Add a "Resync" button to re-read all registered `.ccron/settings.json` files, and a "Remove Folder" action.

**Files:**
- Modify: `ClaudeCron/ClaudeCron/Views/TaskListView.swift`
- Modify: `ClaudeCron/ClaudeCron/Views/ContentView.swift`

**Step 1: Add Resync method to ContentView**

```swift
private func resyncAll() {
    let registry: FolderRegistry = // from environment
    for folder in registry.allFolders {
        importFolder(folder)  // reuses the import logic from Task 6
    }

    // Remove tasks whose taskId no longer exists in any settings file
    let descriptor = FetchDescriptor<ClaudeTask>()
    guard let allTasks = try? modelContext.fetch(descriptor) else { return }

    for task in allTasks {
        let settings = ConfigService.shared.read(folder: task.sourceFolder)
        if settings.tasks[task.taskId] == nil {
            LaunchdService.shared.uninstall(task: task)
            modelContext.delete(task)
        }
    }
    try? modelContext.save()
}
```

**Step 2: Add "Remove Folder" method**

```swift
private func removeFolder(_ folder: String) {
    let registry: FolderRegistry = // from environment
    // Delete all tasks from this folder
    let descriptor = FetchDescriptor<ClaudeTask>(
        predicate: #Predicate { $0.sourceFolder == folder }
    )
    if let tasks = try? modelContext.fetch(descriptor) {
        for task in tasks {
            LaunchdService.shared.uninstall(task: task)
            modelContext.delete(task)
        }
    }
    try? modelContext.save()
    registry.remove(folder)
}
```

**Step 3: Add UI controls**

In TaskListView toolbar or bottom bar:
- Add a "Resync" button (arrow.clockwise icon)
- In the sidebar, group tasks by folder with a context menu "Remove Folder" option

**Step 4: Update onAppear**

Replace `LaunchdService.shared.syncAll(modelContext:)` with `resyncAll()` on app launch (in ContentView's `onAppear`).

**Step 5: Verify manually**

- Add a task to `.ccron/settings.json` by hand → click Resync → task appears
- Remove a task from `.ccron/settings.json` by hand → click Resync → task removed
- Right-click folder → Remove Folder → tasks and launchd jobs gone

**Step 6: Commit**

```bash
git add ClaudeCron/ClaudeCron/Views/ContentView.swift ClaudeCron/ClaudeCron/Views/TaskListView.swift
git commit -m "feat: add Resync and Remove Folder functionality"
```

---

### Task 9: Update Headless Run Mode for New Task Identity

The `--run-task` CLI argument now receives `--source-folder` and `--task-id` instead of a UUID.

**Files:**
- Modify: `ClaudeCron/ClaudeCron/ClaudeCronApp.swift`

**Step 1: Update argument parsing in ClaudeCronApp.init()**

Replace the current UUID-based parsing:

```swift
init() {
    let args = CommandLine.arguments
    if args.contains("--run-task") {
        cliMode = true
        // New format: --run-task --source-folder <folder> --task-id <id>
        guard let folderIdx = args.firstIndex(of: "--source-folder"),
              folderIdx + 1 < args.count,
              let idIdx = args.firstIndex(of: "--task-id"),
              idIdx + 1 < args.count else {
            // Backward compat: try old UUID format
            if let idx = args.firstIndex(of: "--run-task"),
               idx + 1 < args.count {
                runTaskHeadlessLegacy(taskId: args[idx + 1])
            } else {
                print("Missing --source-folder and --task-id")
                exit(1)
            }
            return
        }
        let folder = args[folderIdx + 1]
        let taskId = args[idIdx + 1]
        runTaskHeadless(sourceFolder: folder, taskId: taskId)
    }
}
```

**Step 2: New headless method**

```swift
private func runTaskHeadless(sourceFolder: String, taskId: String) {
    let container = Self.sharedContainer
    let context = container.mainContext
    let descriptor = FetchDescriptor<ClaudeTask>(
        predicate: #Predicate { $0.sourceFolder == sourceFolder && $0.taskId == taskId }
    )
    guard let task = try? context.fetch(descriptor).first else {
        print("Task not found: \(sourceFolder)::\(taskId)")
        exit(1)
    }
    LaunchdService.shared.triggerNow(task: task, modelContext: context, onDone: { exitCode in
        exit(exitCode == 0 ? 0 : 1)
    })
}
```

**Step 3: Keep legacy method for backward compatibility during migration**

Rename existing method to `runTaskHeadlessLegacy`. It stays until all tasks are re-synced.

**Step 4: Commit**

```bash
git add ClaudeCron/ClaudeCron/ClaudeCronApp.swift
git commit -m "feat: update headless run mode to use --source-folder and --task-id"
```

---

### Task 10: Integration Test — Full Round-Trip

Test the complete flow: write JSON → import → edit → write back → resync.

**Files:**
- Create: `ClaudeCron/ClaudeCronTests/ConfigIntegrationTests.swift`

**Step 1: Write the integration test**

```swift
// ClaudeCron/ClaudeCronTests/ConfigIntegrationTests.swift
import XCTest
@testable import ClaudeCron

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

        // Verify daily
        let daily = try XCTUnwrap(loaded.tasks["daily"])
        XCTAssertEqual(daily.schedule.type, "Daily")
        XCTAssertEqual(daily.schedule.hour, 9)
        XCTAssertEqual(daily.schedule.minute, 30)

        // Verify weekly
        let weekly = try XCTUnwrap(loaded.tasks["weekly"])
        XCTAssertEqual(weekly.schedule.weekdays, [2, 4])

        // Verify monthly
        let monthly = try XCTUnwrap(loaded.tasks["monthly"])
        XCTAssertEqual(monthly.schedule.day, 15)

        // Verify interval
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

        // Convert to ClaudeTask
        let task = ClaudeTask()
        task.taskId = "test-task"
        task.sourceFolder = "/Users/me/project"
        task.update(from: def, resolvedPath: "/tmp")

        // Convert back
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

    func testGlobalTaskRequiresPath() throws {
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

        // Initial write
        var file = SettingsFile()
        file.tasks["my-task"] = TaskDefinition(name: "Original", prompt: "first")
        try config.write(file, to: tempDir.path)

        // Read, modify, write back
        var loaded = config.read(folder: tempDir.path)
        loaded.tasks["my-task"]?.name = "Updated"
        loaded.tasks["my-task"]?.prompt = "second"
        try config.write(loaded, to: tempDir.path)

        // Verify
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

        // Remove one task
        var loaded = config.read(folder: tempDir.path)
        loaded.tasks.removeValue(forKey: "task-a")
        try config.write(loaded, to: tempDir.path)

        let reloaded = config.read(folder: tempDir.path)
        XCTAssertNil(reloaded.tasks["task-a"])
        XCTAssertNotNil(reloaded.tasks["task-b"])
    }
}
```

**Step 2: Run tests**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests/ConfigIntegrationTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 3: Run full test suite**

Run: `xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add ClaudeCron/ClaudeCronTests/ConfigIntegrationTests.swift
git commit -m "test: add integration tests for full config round-trip"
```

---

## Execution Order & Dependencies

```
Task 1 (JSON models) ─────┐
                           ├──→ Task 3 (ClaudeTask extensions) ──→ Task 4 (LaunchdService)
Task 2 (ConfigService) ───┘                                              │
                                                                         ▼
Task 5 (FolderRegistry) ──→ Task 6 (Add Folder UI) ──→ Task 7 (Write-back)
                                                              │
                                                              ▼
                                                    Task 8 (Resync/Remove)
                                                              │
                                                              ▼
                                                    Task 9 (Headless mode)
                                                              │
                                                              ▼
                                                    Task 10 (Integration tests)
```

Tasks 1 & 2 can be done in parallel. Task 5 can be done in parallel with Tasks 3 & 4.
