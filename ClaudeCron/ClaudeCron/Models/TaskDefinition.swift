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
    var promptFile: String?             // Relative path to a prompt file (nil = inline prompt)
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

    init(name: String, prompt: String, path: String? = nil, model: String = "sonnet",
         permissionMode: String = "default", schedule: ScheduleDefinition = ScheduleDefinition(type: "Manual"),
         isEnabled: Bool = true, sessionMode: String = "New Session", sessionId: String? = nil,
         allowedTools: [String] = [], disallowedTools: [String] = [],
         notifyOnStart: Bool = false, notifyOnEnd: Bool = true) {
        self.name = name
        self.prompt = prompt
        self.path = path
        self.model = model
        self.permissionMode = permissionMode
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.sessionMode = sessionMode
        self.sessionId = sessionId
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.notifyOnStart = notifyOnStart
        self.notifyOnEnd = notifyOnEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        promptFile = try container.decodeIfPresent(String.self, forKey: .promptFile)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "sonnet"
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? "default"
        schedule = try container.decodeIfPresent(ScheduleDefinition.self, forKey: .schedule) ?? ScheduleDefinition(type: "Manual")
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sessionMode = try container.decodeIfPresent(String.self, forKey: .sessionMode) ?? "New Session"
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        allowedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        disallowedTools = try container.decodeIfPresent([String].self, forKey: .disallowedTools) ?? []
        notifyOnStart = try container.decodeIfPresent(Bool.self, forKey: .notifyOnStart) ?? false
        notifyOnEnd = try container.decodeIfPresent(Bool.self, forKey: .notifyOnEnd) ?? true
    }
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
