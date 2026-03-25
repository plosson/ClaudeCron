import Foundation
import SwiftData
import UserNotifications

@Observable
final class LaunchdService {
    static let shared = LaunchdService()

    private let plistPrefix = "com.claudecron.task."
    private var launchAgentsDir: String {
        NSHomeDirectory() + "/Library/LaunchAgents"
    }

    // MARK: - Plist lifecycle

    func install(task: ClaudeTask) {
        guard task.isEnabled else {
            uninstall(taskId: task.id)
            return
        }

        let label = plistLabel(for: task.id)
        let plistPath = plistPath(for: task.id)

        unload(label: label)

        let plist = buildPlist(task: task, label: label)

        let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try? data?.write(to: URL(fileURLWithPath: plistPath))

        load(plistPath: plistPath)
    }

    func uninstall(taskId: UUID) {
        let label = plistLabel(for: taskId)
        let path = plistPath(for: taskId)

        unload(label: label)
        try? FileManager.default.removeItem(atPath: path)
    }

    func syncAll(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ClaudeTask>()
        guard let tasks = try? modelContext.fetch(descriptor) else { return }

        let validIds = Set(tasks.map { plistLabel(for: $0.id) })
        if let files = try? FileManager.default.contentsOfDirectory(atPath: launchAgentsDir) {
            for file in files where file.hasPrefix(plistPrefix) && file.hasSuffix(".plist") {
                let label = String(file.dropLast(6))
                if !validIds.contains(label) {
                    unload(label: label)
                    try? FileManager.default.removeItem(
                        atPath: (launchAgentsDir as NSString).appendingPathComponent(file)
                    )
                }
            }
        }

        for task in tasks {
            if task.isEnabled {
                install(task: task)
            } else {
                uninstall(taskId: task.id)
            }
        }
    }

    // MARK: - Build plist dictionary

    func buildPlist(task: ClaudeTask, label: String) -> [String: Any] {
        let appPath = Bundle.main.executablePath ?? "/usr/local/bin/ClaudeCron"
        let schedule = task.schedule
        let calendar = Calendar.current

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [appPath, "--run-task", task.id.uuidString],
            "StandardOutPath": logPath(for: task.id, stream: "stdout"),
            "StandardErrorPath": logPath(for: task.id, stream: "stderr"),
            "RunAtLoad": false,
        ]

        switch schedule.type {
        case .daily:
            let hour = calendar.component(.hour, from: schedule.time)
            let minute = calendar.component(.minute, from: schedule.time)
            plist["StartCalendarInterval"] = [
                "Hour": hour,
                "Minute": minute,
            ]

        case .weekly:
            let hour = calendar.component(.hour, from: schedule.time)
            let minute = calendar.component(.minute, from: schedule.time)
            let intervals: [[String: Int]] = schedule.weekdays.sorted().map { weekday in
                ["Weekday": weekday - 1, "Hour": hour, "Minute": minute]
            }
            plist["StartCalendarInterval"] = intervals

        case .interval:
            plist["StartInterval"] = schedule.intervalMinutes * 60

        case .monthly:
            let hour = calendar.component(.hour, from: schedule.time)
            let minute = calendar.component(.minute, from: schedule.time)
            let day = calendar.component(.day, from: schedule.time)
            plist["StartCalendarInterval"] = [
                "Day": day,
                "Hour": hour,
                "Minute": minute,
            ]

        case .manual:
            break // No schedule — manual trigger only
        }

        return plist
    }

    // MARK: - launchctl load/unload

    private func load(plistPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func unload(label: String) {
        let path = plistPath(for: label)
        guard FileManager.default.fileExists(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Helpers

    private func plistLabel(for taskId: UUID) -> String {
        "\(plistPrefix)\(taskId.uuidString)"
    }

    private func plistPath(for taskId: UUID) -> String {
        (launchAgentsDir as NSString).appendingPathComponent("\(plistLabel(for: taskId)).plist")
    }

    private func plistPath(for label: String) -> String {
        (launchAgentsDir as NSString).appendingPathComponent("\(label).plist")
    }

    private func logPath(for taskId: UUID, stream: String) -> String {
        let logsDir = NSHomeDirectory() + "/Library/Logs/ClaudeCron"
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        return (logsDir as NSString).appendingPathComponent("\(taskId.uuidString)-\(stream).log")
    }

    // MARK: - Manual trigger (run immediately, bypassing schedule)

    func triggerNow(task: ClaudeTask, modelContext: ModelContext) {
        let run = TaskRun(task: task)
        modelContext.insert(run)
        try? modelContext.save()

        if task.notifyOnStart {
            sendNotification(title: "Task Started", body: task.name)
        }

        let allowedTools = task.allowedTools.split(separator: ",").map(String.init)
        let disallowedTools = task.disallowedTools.split(separator: ",").map(String.init)

        _ = ClaudeService.shared.runTask(
            prompt: task.prompt,
            directory: task.directory,
            model: task.model,
            permissionMode: task.permissionMode,
            sessionMode: SessionMode(rawValue: task.sessionMode) ?? .new,
            sessionId: task.sessionId,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools,
            onOutput: { output in
                run.rawOutput += output
                for line in output.components(separatedBy: "\n") {
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let result = json["result"] as? String {
                        run.formattedOutput += result + "\n"
                    }
                }
                try? modelContext.save()
            },
            onComplete: { exitCode, sessionId in
                run.endedAt = Date()
                run.exitCode = Int(exitCode)
                run.runStatus = exitCode == 0 ? .succeeded : .failed
                if let sid = sessionId {
                    run.sessionId = sid
                    task.sessionId = sid
                }
                try? modelContext.save()

                if task.notifyOnEnd {
                    let status = exitCode == 0 ? "completed" : "failed"
                    self.sendNotification(title: "Task \(status.capitalized)", body: task.name)
                }
            }
        )
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
