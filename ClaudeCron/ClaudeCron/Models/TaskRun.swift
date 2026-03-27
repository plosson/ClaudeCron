import Foundation
import SwiftData

enum RunStatus: String, Codable {
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

@Model
final class TaskRun {
    var id: UUID
    var task: ClaudeTask?
    var status: String // RunStatus rawValue
    var startedAt: Date
    var endedAt: Date?
    var rawOutput: String
    var formattedOutput: String
    var debugLog: String
    var exitCode: Int?
    var sessionId: String?

    @Transient var processId: UUID?

    var runStatus: RunStatus {
        get { RunStatus(rawValue: status) ?? .failed }
        set { status = newValue.rawValue }
    }

    var duration: TimeInterval? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    init(task: ClaudeTask) {
        self.id = UUID()
        self.task = task
        self.status = RunStatus.running.rawValue
        self.startedAt = Date()
        self.rawOutput = ""
        self.formattedOutput = ""
        self.debugLog = ""
    }

    func log(_ message: String) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        debugLog += "[\(timestamp)] \(message)\n"
    }

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
