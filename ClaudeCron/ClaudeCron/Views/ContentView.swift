import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @State private var selectedTask: ClaudeTask?
    @State private var selectedRun: TaskRun?
    @State private var showingNewTask = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            TaskListView(selectedTask: $selectedTask, showingNewTask: $showingNewTask)
                .frame(minWidth: 220)
        } content: {
            if let task = selectedTask {
                Text("Task: \(task.name)") // Placeholder — Task 5 will implement
                    .frame(minWidth: 300)
            } else {
                ContentUnavailableView("Select a Task", systemImage: "clock.badge.questionmark")
            }
        } detail: {
            ContentUnavailableView("Select a Run", systemImage: "terminal")
        }
        .frame(minWidth: 900, minHeight: 500)
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            LaunchdService.shared.syncAll(modelContext: modelContext)
        }
    }
}
