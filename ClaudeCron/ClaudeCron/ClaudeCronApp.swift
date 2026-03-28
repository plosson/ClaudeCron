import SwiftUI
import SwiftData
import Sparkle

extension Notification.Name {
    static let newTaskShortcut = Notification.Name("newTaskShortcut")
    static let runTaskShortcut = Notification.Name("runTaskShortcut")
    static let saveTaskShortcut = Notification.Name("saveTaskShortcut")
    static let toggleTaskShortcut = Notification.Name("toggleTaskShortcut")
    static let deleteTaskShortcut = Notification.Name("deleteTaskShortcut")
    static let backToTasksShortcut = Notification.Name("backToTasksShortcut")
}

@main
struct ClaudeCronApp: App {
    @State private var cliMode = false
    @State private var folderRegistry = FolderRegistry()
    @State private var updateService = UpdateService.shared

    static let sharedContainer: ModelContainer = {
        let schema = Schema([ClaudeTask.self, TaskRun.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed — delete old store and retry
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    init() {
        let args = CommandLine.arguments
        let isCLI = args[0].hasSuffix("/\(CLIInstallService.cliName)")

        if isCLI && !CLIInstallService.validateAppBundle(symlinkAt: args[0]) {
            print("Claude Cron app not found. It may have been uninstalled.")
            print("To remove this CLI tool, run: rm \(args[0])")
            exit(1)
        }

        if isCLI && !args.contains("--run-task") {
            cliMode = true
            printCLIHelp()
            exit(0)
        }

        if args.contains("--run-task") {
            cliMode = true
            // New format: --run-task --source-folder <folder> --task-id <id>
            if let folderIdx = args.firstIndex(of: "--source-folder"),
               folderIdx + 1 < args.count,
               let idIdx = args.firstIndex(of: "--task-id"),
               idIdx + 1 < args.count {
                let folder = args[folderIdx + 1]
                let taskId = args[idIdx + 1]
                let descriptor = FetchDescriptor<ClaudeTask>(
                    predicate: #Predicate { $0.sourceFolder == folder && $0.taskId == taskId }
                )
                runTaskHeadless(descriptor: descriptor, errorLabel: "\(folder)::\(taskId)")
            } else if let idx = args.firstIndex(of: "--run-task"),
                      idx + 1 < args.count,
                      args[idx + 1] != "--source-folder" {
                // Legacy format: --run-task <UUID>
                let taskIdString = args[idx + 1]
                guard let uuid = UUID(uuidString: taskIdString) else {
                    print("Invalid task ID: \(taskIdString)")
                    exit(1)
                }
                let descriptor = FetchDescriptor<ClaudeTask>(
                    predicate: #Predicate { $0.id == uuid }
                )
                runTaskHeadless(descriptor: descriptor, errorLabel: taskIdString)
            } else {
                print("Usage: --run-task --source-folder <folder> --task-id <id>")
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if !cliMode {
                ContentView()
                    .environment(folderRegistry)
                    .environment(updateService)
                    .onAppear {
                        updateService.startUpdater()
                        cleanupStaleRuns()
                    }
            }
        }
        .modelContainer(Self.sharedContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .newTaskShortcut, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Task") {
                Button("Run Now") {
                    NotificationCenter.default.post(name: .runTaskShortcut, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Save") {
                    NotificationCenter.default.post(name: .saveTaskShortcut, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Toggle Enabled") {
                    NotificationCenter.default.post(name: .toggleTaskShortcut, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Delete Task") {
                    NotificationCenter.default.post(name: .deleteTaskShortcut, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Back to Tasks") {
                    NotificationCenter.default.post(name: .backToTasksShortcut, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            CommandGroup(replacing: .help) {
                Button("Check for Updates...") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)

                Divider()

                if CLIInstallService.isInstalled {
                    Button("Uninstall Command Line Tool (ccron)") {
                        try? CLIInstallService.uninstall()
                    }
                } else {
                    Button("Install Command Line Tool (ccron)") {
                        try? CLIInstallService.install()
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .modelContainer(Self.sharedContainer)
                .environment(updateService)
                .frame(minWidth: 420, minHeight: 350)
        }

        MenuBarExtra("Claude Cron", image: "MenuBarIcon") {
            MenuBarView()
                .modelContainer(Self.sharedContainer)
                .environment(folderRegistry)
                .environment(updateService)
        }
    }

    /// Mark any "Running" TaskRuns as failed on startup — they are stale from a previous crash/quit
    private func cleanupStaleRuns() {
        let context = Self.sharedContainer.mainContext
        let runningStatus = RunStatus.running.rawValue
        let descriptor = FetchDescriptor<TaskRun>(
            predicate: #Predicate { $0.status == runningStatus }
        )
        guard let staleRuns = try? context.fetch(descriptor), !staleRuns.isEmpty else { return }
        for run in staleRuns {
            run.runStatus = .failed
            run.endedAt = Date()
            run.log("Marked as failed — app was restarted while task was running")
        }
        try? context.save()
        print("[ClaudeCron] Cleaned up \(staleRuns.count) stale running task(s)")
    }

    private func printCLIHelp() {
        let name = CLIInstallService.cliName
        print("""
        \(name) - Claude Cron command line tool

        Usage:
          \(name) --run-task --source-folder <folder> --task-id <id>
          \(name) --help
        """)
    }

    private func runTaskHeadless(descriptor: FetchDescriptor<ClaudeTask>, errorLabel: String) {
        let context = Self.sharedContainer.mainContext
        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found: \(errorLabel)")
            exit(1)
        }
        LaunchdService.shared.triggerNow(task: task, modelContext: context, onDone: { exitCode in
            exit(exitCode == 0 ? 0 : 1)
        })
    }
}
