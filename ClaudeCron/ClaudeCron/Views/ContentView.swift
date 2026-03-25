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
                TaskDetailView(task: task, selectedRun: $selectedRun)
                    .frame(minWidth: 300)
            } else {
                ContentUnavailableView("Select a Task", systemImage: "clock.badge.questionmark")
            }
        } detail: {
            if let run = selectedRun {
                RunDetailView(run: run)
                    .frame(minWidth: 400)
            } else {
                ContentUnavailableView("Select a Run", systemImage: "terminal")
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            LaunchdService.shared.syncAll(modelContext: modelContext)
        }
    }
}
