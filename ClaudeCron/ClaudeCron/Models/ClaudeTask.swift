import Foundation
import SwiftData

enum ClaudeModel: String, Codable, CaseIterable {
    case opus = "opus"
    case sonnet = "sonnet"
    case haiku = "haiku"
}

enum PermissionMode: String, Codable, CaseIterable {
    case default_ = "default"
    case bypass = "bypassPermissions"
    case plan = "plan"
    case acceptEdits = "acceptEdits"
}

enum SessionMode: String, Codable, CaseIterable {
    case new = "New Session"
    case resume = "Resume Session"
    case fork = "Fork Session"
}

@Model
final class ClaudeTask {
    var id: UUID
    var name: String
    var prompt: String
    var directory: String
    var model: String // ClaudeModel rawValue
    var permissionMode: String // PermissionMode rawValue
    var scheduleData: Data? // JSON-encoded TaskSchedule
    var isEnabled: Bool
    var sessionMode: String // SessionMode rawValue
    var sessionId: String?
    var allowedTools: String // comma-separated
    var disallowedTools: String // comma-separated
    var notifyOnStart: Bool
    var notifyOnEnd: Bool
    var createdAt: Date
    var sourceFolder: String = ""   // folder that owns this task's settings.json
    var taskId: String = ""         // string key in the tasks dict (e.g. "daily-cleanup")
    var promptFile: String = ""     // relative path to a prompt file (empty = inline prompt)
    var taskDescription: String = "" // AI-generated summary of what the task does
    var avatarConfigData: Data?      // JSON-encoded AvatarConfig (nil = auto-generated)

    @Relationship(deleteRule: .cascade, inverse: \TaskRun.task)
    var runs: [TaskRun]

    var schedule: TaskSchedule {
        get {
            guard let data = scheduleData else { return TaskSchedule() }
            return (try? JSONDecoder().decode(TaskSchedule.self, from: data)) ?? TaskSchedule()
        }
        set {
            scheduleData = try? JSONEncoder().encode(newValue)
        }
    }

    var avatarConfig: AvatarConfig {
        get {
            if let data = avatarConfigData,
               let config = try? JSONDecoder().decode(AvatarConfig.self, from: data) {
                return config
            }
            return .generate(from: id.uuidString)
        }
        set {
            avatarConfigData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        name: String = "",
        prompt: String = "",
        directory: String = "",
        model: ClaudeModel = .sonnet,
        permissionMode: PermissionMode = .default_,
        schedule: TaskSchedule = TaskSchedule(),
        isEnabled: Bool = true,
        sessionMode: SessionMode = .new,
        allowedTools: String = "",
        disallowedTools: String = "",
        notifyOnStart: Bool = false,
        notifyOnEnd: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.prompt = prompt
        self.directory = directory
        self.model = model.rawValue
        self.permissionMode = permissionMode.rawValue
        self.scheduleData = try? JSONEncoder().encode(schedule)
        self.isEnabled = isEnabled
        self.sessionMode = sessionMode.rawValue
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.notifyOnStart = notifyOnStart
        self.notifyOnEnd = notifyOnEnd
        self.createdAt = Date()
        self.runs = []
    }

    /// Resolve the effective prompt — reads from file if promptFile is set
    var resolvedPrompt: String {
        guard !promptFile.isEmpty else { return prompt }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(promptFile)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? prompt
    }

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
        if !promptFile.isEmpty {
            def.promptFile = promptFile
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
        promptFile = def.promptFile ?? ""
    }
}
