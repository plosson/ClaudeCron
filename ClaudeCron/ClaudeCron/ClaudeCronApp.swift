import SwiftUI
import SwiftData
import Sparkle

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
                    .onAppear { updateService.startUpdater() }
            }
        }
        .modelContainer(Self.sharedContainer)

        MenuBarExtra("Claude Cron", image: "MenuBarIcon") {
            MenuBarView()
                .modelContainer(Self.sharedContainer)
                .environment(folderRegistry)
                .environment(updateService)
        }
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
