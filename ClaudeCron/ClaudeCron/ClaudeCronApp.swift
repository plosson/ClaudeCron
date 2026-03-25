import SwiftUI
import SwiftData

@main
struct ClaudeCronApp: App {
    @State private var cliMode = false
    @State private var folderRegistry = FolderRegistry()

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
        if args.contains("--run-task") {
            cliMode = true
            // New format: --run-task --source-folder <folder> --task-id <id>
            if let folderIdx = args.firstIndex(of: "--source-folder"),
               folderIdx + 1 < args.count,
               let idIdx = args.firstIndex(of: "--task-id"),
               idIdx + 1 < args.count {
                let folder = args[folderIdx + 1]
                let taskId = args[idIdx + 1]
                runTaskHeadless(sourceFolder: folder, taskId: taskId)
            } else if let idx = args.firstIndex(of: "--run-task"),
                      idx + 1 < args.count,
                      args[idx + 1] != "--source-folder" {
                // Legacy format: --run-task <UUID>
                runTaskHeadlessLegacy(taskId: args[idx + 1])
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
            }
        }
        .modelContainer(Self.sharedContainer)

        MenuBarExtra("Claude Cron", image: "MenuBarIcon") {
            MenuBarView()
                .modelContainer(Self.sharedContainer)
                .environment(folderRegistry)
        }
    }

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

    private func runTaskHeadlessLegacy(taskId: String) {
        guard let uuid = UUID(uuidString: taskId) else {
            print("Invalid task ID: \(taskId)")
            exit(1)
        }

        let container = Self.sharedContainer

        let context = container.mainContext
        let descriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found: \(taskId)")
            exit(1)
        }

        LaunchdService.shared.triggerNow(task: task, modelContext: context, onDone: { exitCode in
            exit(exitCode == 0 ? 0 : 1)
        })
    }
}
