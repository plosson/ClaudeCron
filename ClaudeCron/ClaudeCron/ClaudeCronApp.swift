import SwiftUI
import SwiftData

@main
struct ClaudeCronApp: App {
    @State private var cliMode = false

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
        .modelContainer(for: [ClaudeTask.self, TaskRun.self])

        MenuBarExtra("Claude Cron", systemImage: "clock.badge.checkmark") {
            MenuBarView()
                .modelContainer(for: [ClaudeTask.self, TaskRun.self])
        }
    }

    private func runTaskHeadless(taskId: String) {
        guard let uuid = UUID(uuidString: taskId) else {
            print("Invalid task ID: \(taskId)")
            exit(1)
        }

        guard let container = try? ModelContainer(for: ClaudeTask.self, TaskRun.self) else {
            print("Failed to open data store")
            exit(1)
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let task = try? context.fetch(descriptor).first else {
            print("Task not found: \(taskId)")
            exit(1)
        }

        LaunchdService.shared.triggerNow(task: task, modelContext: context)
        // The app will stay alive via the run loop until the Claude process completes
        // and the onComplete callback fires. The process termination handler will handle exit.
    }
}
