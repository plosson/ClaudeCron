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
}
