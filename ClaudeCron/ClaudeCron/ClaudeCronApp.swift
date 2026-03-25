import SwiftUI
import SwiftData

@main
struct ClaudeCronApp: App {
    @State private var cliMode = false

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
        if let idx = args.firstIndex(of: "--run-task"),
           idx + 1 < args.count {
            let taskIdString = args[idx + 1]
            cliMode = true
            runTaskHeadless(taskId: taskIdString)
        }
    }

    var body: some Scene {
        WindowGroup {
            if !cliMode {
                ContentView()
            }
        }
        .modelContainer(Self.sharedContainer)

        MenuBarExtra("Claude Cron", systemImage: "clock.badge.checkmark") {
            MenuBarView()
                .modelContainer(Self.sharedContainer)
        }
    }

    private func runTaskHeadless(taskId: String) {
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
