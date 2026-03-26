import Foundation
import SwiftData
import UserNotifications

@Observable
@MainActor
final class LaunchdService {
    static let shared = LaunchdService()

    private let plistPrefix = "com.claudecron.task."
    private var launchAgentsDir: String {
        NSHomeDirectory() + "/Library/LaunchAgents"
    }

    // MARK: - Plist lifecycle

    func install(task: ClaudeTask) {
        guard task.isEnabled else {
            uninstall(task: task)
            return
        }

        let label = plistLabel(for: task)
        let path = plistPath(for: task)

        unload(label: label)

        let plist = buildPlist(task: task)

        let data: Data?
        do {
            data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        } catch {
            print("[LaunchdService] Failed to serialize plist for \(label): \(error.localizedDescription)")
            return
        }
        guard let plistData = data else { return }
        do {
            try plistData.write(to: URL(fileURLWithPath: path))
        } catch {
            print("[LaunchdService] Failed to write plist at \(path): \(error.localizedDescription)")
            return
        }

        load(plistPath: path)
    }

    func uninstall(task: ClaudeTask) {
        let label = plistLabel(for: task)
        let path = plistPath(for: task)

        unload(label: label)
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            print("[LaunchdService] Failed to remove plist at \(path): \(error.localizedDescription)")
        }
    }

    func uninstall(taskId: UUID) {
        let label = plistLabel(for: taskId)
        let path = plistPath(for: taskId)

        unload(label: label)
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            print("[LaunchdService] Failed to remove plist at \(path): \(error.localizedDescription)")
        }
    }

    func syncAll(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ClaudeTask>()
        guard let tasks = try? modelContext.fetch(descriptor) else { return }

        let validLabels = Set(tasks.map { plistLabel(for: $0) })
        if let files = try? FileManager.default.contentsOfDirectory(atPath: launchAgentsDir) {
            for file in files where file.hasPrefix(plistPrefix) && file.hasSuffix(".plist") {
                let label = String(file.dropLast(6))
                if !validLabels.contains(label) {
                    unload(label: label)
                    let filePath = (launchAgentsDir as NSString).appendingPathComponent(file)
                    do {
                        try FileManager.default.removeItem(atPath: filePath)
                    } catch {
                        print("[LaunchdService] Failed to remove orphan plist \(file): \(error.localizedDescription)")
                    }
                }
            }
        }

        for task in tasks {
            if task.isEnabled {
                install(task: task)
            } else {
                uninstall(task: task)
            }
        }
    }

    // MARK: - Build plist dictionary

    func buildPlist(task: ClaudeTask) -> [String: Any] {
        let label = plistLabel(for: task)
        let appPath = Bundle.main.executablePath ?? "/usr/local/bin/ClaudeCron"
        let schedule = task.schedule
        let calendar = Calendar.current

        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [appPath, "--run-task", "--source-folder", task.sourceFolder, "--task-id", task.taskId],
            "StandardOutPath": logPath(for: task, stream: "stdout"),
            "StandardErrorPath": logPath(for: task, stream: "stderr"),
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
            let intervals: [[String: Int]] = schedule.weekdays.sorted()
                .filter { (1...7).contains($0) }
                .map { weekday in
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

    func plistLabel(for task: ClaudeTask) -> String {
        let key = task.compositeKey
        let hashValue = key.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = hash &* 33 &+ UInt64(byte)
        }
        return "\(plistPrefix)\(String(hashValue, radix: 16))"
    }

    private func plistPath(for task: ClaudeTask) -> String {
        (launchAgentsDir as NSString).appendingPathComponent("\(plistLabel(for: task)).plist")
    }

    private func plistLabel(for taskId: UUID) -> String {
        "\(plistPrefix)\(taskId.uuidString)"
    }

    private func plistPath(for taskId: UUID) -> String {
        (launchAgentsDir as NSString).appendingPathComponent("\(plistLabel(for: taskId)).plist")
    }

    private func plistPath(for label: String) -> String {
        (launchAgentsDir as NSString).appendingPathComponent("\(label).plist")
    }

    private func logPath(for task: ClaudeTask, stream: String) -> String {
        let logsDir = NSHomeDirectory() + "/Library/Logs/ClaudeCron"
        do {
            try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        } catch {
            print("[LaunchdService] Failed to create logs directory: \(error.localizedDescription)")
        }
        let label = plistLabel(for: task)
        return (logsDir as NSString).appendingPathComponent("\(label)-\(stream).log")
    }

    // MARK: - Manual trigger (run immediately, bypassing schedule)

    func triggerNow(task: ClaudeTask, modelContext: ModelContext, onDone: ((Int32) -> Void)? = nil) {
        let run = TaskRun(task: task)
        modelContext.insert(run)
        do {
            try modelContext.save()
        } catch {
            print("[LaunchdService] Failed to save context after insert: \(error.localizedDescription)")
        }

        run.log("Task: \(task.name) (id: \(task.compositeKey))")
        run.log("Prompt: \(task.prompt)")
        run.log("Model: \(task.model), Permissions: \(task.permissionMode)")
        run.log("Session mode: \(task.sessionMode)")

        if task.notifyOnStart {
            sendNotification(title: "Task Started", body: task.name)
        }

        let allowedTools = task.allowedTools.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let disallowedTools = task.disallowedTools.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

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
                for line in output.components(separatedBy: "\n") where !line.isEmpty {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                    let type = json["type"] as? String

                    // Extract session_id from init event
                    if type == "system",
                       let subtype = json["subtype"] as? String, subtype == "init",
                       let sid = json["session_id"] as? String {
                        run.sessionId = sid
                        task.sessionId = sid
                    }

                    // Extract streaming text from assistant messages
                    if type == "assistant",
                       let message = json["message"] as? [String: Any],
                       let content = message["content"] as? [[String: Any]] {
                        for block in content {
                            if let text = block["text"] as? String {
                                run.formattedOutput += text
                            }
                        }
                    }

                    // Extract final result
                    if type == "result",
                       let result = json["result"] as? String {
                        // Replace streaming text with final result
                        run.formattedOutput = result
                    }
                }
                do {
                    try modelContext.save()
                } catch {
                    print("[LaunchdService] Failed to save context on output: \(error.localizedDescription)")
                }
            },
            onLog: { message in
                run.log(message)
                do {
                    try modelContext.save()
                } catch {
                    print("[LaunchdService] Failed to save context on log: \(error.localizedDescription)")
                }
            },
            onComplete: { exitCode, sessionId in
                run.endedAt = Date()
                run.exitCode = Int(exitCode)
                run.runStatus = exitCode == 0 ? .succeeded : .failed
                // Fallback: use stderr session ID if not already captured from stream
                if run.sessionId == nil, let sid = sessionId {
                    run.sessionId = sid
                    task.sessionId = sid
                }
                do {
                    try modelContext.save()
                } catch {
                    print("[LaunchdService] Failed to save context on complete: \(error.localizedDescription)")
                }

                if task.notifyOnEnd {
                    let status = exitCode == 0 ? "completed" : "failed"
                    self.sendNotification(title: "Task \(status.capitalized)", body: task.name)
                }

                onDone?(exitCode)
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
