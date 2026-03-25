import SwiftUI
import SwiftData

@main
struct ClaudeCronApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ClaudeTask.self, TaskRun.self])
    }
}
