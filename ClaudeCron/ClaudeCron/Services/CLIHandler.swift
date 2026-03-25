import Foundation
import SwiftData

enum CLIHandler {
    static func run(container: ModelContainer) -> Never {
        let args = Array(CommandLine.arguments.dropFirst()) // drop executable path

        guard let command = args.first else {
            printHelp()
            exit(0)
        }

        let subargs = Array(args.dropFirst())

        switch command {
        case "list":
            cmdList(container: container)
        case "show":
            cmdShow(subargs: subargs, container: container)
        case "create":
            cmdCreate(subargs: subargs, container: container)
        case "edit":
            cmdEdit(subargs: subargs, container: container)
        case "delete":
            cmdDelete(subargs: subargs, container: container)
        case "enable":
            cmdEnable(subargs: subargs, container: container)
        case "disable":
            cmdDisable(subargs: subargs, container: container)
        case "run":
            cmdRun(subargs: subargs, container: container)
        case "history":
            cmdHistory(subargs: subargs, container: container)
        case "log":
            cmdLog(subargs: subargs, container: container)
        case "folders":
            cmdFolders(subargs: subargs, container: container)
        case "sync":
            cmdSync(container: container)
        case "--run-task":
            // Legacy/internal: re-parse from full args for backward compat
            cmdRunTask(container: container)
        case "--help", "-h", "help":
            printHelp()
            exit(0)
        default:
            printError("Unknown command: \(command)")
            printHelp()
            exit(1)
        }

        exit(0)
    }

    // MARK: - Help

    static func printHelp() {
        let name = CLIInstallService.cliName
        print("""
        \(name) - Claude Cron command line tool

        TASK MANAGEMENT
          \(name) list                            List all tasks
          \(name) show <task-id>                  Show task details and upcoming runs
          \(name) create <name> [options]         Create a new task
          \(name) edit <task-id> [options]         Edit an existing task
          \(name) delete <task-id>                Delete a task
          \(name) enable <task-id>                Enable a task
          \(name) disable <task-id>               Disable a task

        EXECUTION
          \(name) run <task-id>                   Run a task immediately
          \(name) history [task-id]               Show run history
          \(name) log <run-id>                    Show output of a specific run

        FOLDERS
          \(name) folders                         List registered folders
          \(name) folders add <path>              Register a project folder
          \(name) folders remove <path>           Unregister a folder and its tasks

        MAINTENANCE
          \(name) sync                            Resync tasks from settings.json files

        OPTIONS FOR create/edit
          --prompt <text>                         Prompt or command to run
          --directory <path>                      Working directory
          --scope global|local                    Task scope (default: local to cwd)
          --model opus|sonnet|haiku               Model (default: sonnet)
          --permissions default|bypass|plan|acceptEdits
          --schedule manual|daily|weekly|monthly|interval
          --time HH:MM                            Time for daily/weekly/monthly
          --weekdays mon,tue,wed,...              Days for weekly schedule
          --day <1-31>                            Day for monthly schedule
          --interval <minutes>                    Minutes for interval schedule
          --session-mode new|resume|fork
          --allowed-tools <tools>                 Comma-separated tool names
          --disallowed-tools <tools>              Comma-separated tool names
          --notify-start                          Enable start notification
          --notify-end / --no-notify-end          Toggle end notification

        TASK ID FORMAT
          Use the task slug (e.g. "daily-cleanup").
          If ambiguous across folders, use "folder::task-id".
        """)
    }

    // MARK: - Helpers

    static func printError(_ message: String) {
        FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    }

    /// Resolve a task-id argument. Supports "task-id" or "folder::task-id".
    static func resolveTask(_ identifier: String, container: ModelContainer) -> ClaudeTask? {
        let context = ModelContext(container)
        let parts = identifier.split(separator: "::", maxSplits: 1).map(String.init)

        if parts.count == 2 {
            let folder = parts[0]
            let taskId = parts[1]
            let descriptor = FetchDescriptor<ClaudeTask>(
                predicate: #Predicate { $0.sourceFolder == folder && $0.taskId == taskId }
            )
            return try? context.fetch(descriptor).first
        }

        // Single task-id — find across all folders
        let taskId = identifier
        let descriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { $0.taskId == taskId }
        )
        guard let matches = try? context.fetch(descriptor) else { return nil }
        if matches.count > 1 {
            printError("Ambiguous task-id '\(taskId)'. Found in multiple folders:")
            for task in matches {
                printError("  \(task.sourceFolder)::\(task.taskId)")
            }
            printError("Use 'folder::task-id' format to disambiguate.")
            return nil
        }
        return matches.first
    }

    /// Slugify a name to a task-id (same logic as TaskFormView).
    static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Parse a flag value from args: --flag <value>
    static func flagValue(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    /// Check if a boolean flag is present
    static func hasFlag(_ flag: String, in args: [String]) -> Bool {
        args.contains(flag)
    }

    /// Format a folder path for display (abbreviate home dir)
    static func displayFolder(_ folder: String) -> String {
        let home = NSHomeDirectory()
        if folder == home { return "~ (global)" }
        if folder.hasPrefix(home) {
            return "~" + folder.dropFirst(home.count)
        }
        return folder
    }

    /// Format duration
    static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 { return "\(minutes)m \(secs)s" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    // MARK: - list

    static func cmdList(container: ModelContainer) {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClaudeTask>()
        descriptor.sortBy = [SortDescriptor(\.sourceFolder), SortDescriptor(\.name)]
        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            print("No tasks found.")
            return
        }

        // Table header
        let fmt = "%-8s  %-25s  %-8s  %-25s  %s"
        print(String(format: fmt, "STATUS", "NAME", "MODEL", "SCHEDULE", "FOLDER"))
        print(String(repeating: "-", count: 90))

        for task in tasks {
            let status = task.isEnabled ? "●" : "○"
            let name = String(task.name.prefix(25))
            let model = task.model
            let schedule = String(task.schedule.displaySummary.prefix(25))
            let folder = displayFolder(task.sourceFolder)
            print(String(format: "%-8s  %-25s  %-8s  %-25s  %s",
                status, name, model, schedule, folder))
        }

        print("\n\(tasks.count) task(s)")
    }

    // MARK: - show

    static func cmdShow(subargs: [String], container: ModelContainer) {
        guard let taskId = subargs.first else {
            printError("Usage: ccron show <task-id>")
            exit(1)
        }
        guard let task = resolveTask(taskId, container: container) else {
            printError("Task not found: \(taskId)")
            exit(1)
        }

        print("Name:         \(task.name)")
        print("Task ID:      \(task.taskId)")
        print("Folder:       \(displayFolder(task.sourceFolder))")
        print("Status:       \(task.isEnabled ? "Enabled" : "Disabled")")
        print("Model:        \(task.model)")
        print("Permissions:  \(task.permissionMode)")
        print("Schedule:     \(task.schedule.displaySummary)")
        print("Session:      \(task.sessionMode)")
        if let sid = task.sessionId { print("Session ID:   \(sid)") }
        print("Directory:    \(task.directory)")
        print("")
        print("Prompt:")
        print("  \(task.prompt)")

        if !task.allowedTools.isEmpty {
            print("\nAllowed tools: \(task.allowedTools)")
        }
        if !task.disallowedTools.isEmpty {
            print("\nDisallowed tools: \(task.disallowedTools)")
        }

        print("\nNotifications: start=\(task.notifyOnStart ? "on" : "off"), end=\(task.notifyOnEnd ? "on" : "off")")

        // Upcoming runs
        let upcoming = ScheduleCalculator.nextRuns(for: task.schedule, count: 3)
        if !upcoming.isEmpty {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            print("\nUpcoming runs:")
            for date in upcoming {
                print("  \(fmt.string(from: date))")
            }
        }

        // Recent runs
        let context = ModelContext(container)
        let taskUUID = task.id
        var runDescriptor = FetchDescriptor<TaskRun>(
            predicate: #Predicate { $0.task?.id == taskUUID }
        )
        runDescriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        runDescriptor.fetchLimit = 5
        if let runs = try? context.fetch(runDescriptor), !runs.isEmpty {
            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .short
            dateFmt.timeStyle = .short
            print("\nRecent runs:")
            let header = String(format: "  %-20s  %-10s  %-10s  %s", "DATE", "STATUS", "DURATION", "RUN ID")
            print(header)
            for run in runs {
                let date = dateFmt.string(from: run.startedAt)
                let status = run.runStatus.rawValue
                let duration = run.duration.map { formatDuration($0) } ?? "-"
                let runId = String(run.id.uuidString.prefix(8))
                print(String(format: "  %-20s  %-10s  %-10s  %s", date, status, duration, runId))
            }
        }
    }

    // MARK: - Command stubs (implemented in subsequent tasks)

    static func cmdCreate(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdEdit(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdDelete(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdEnable(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdDisable(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdRun(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdHistory(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdLog(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdFolders(subargs: [String], container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdSync(container: ModelContainer) { printError("Not yet implemented"); exit(1) }
    static func cmdRunTask(container: ModelContainer) { printError("Not yet implemented"); exit(1) }
}
