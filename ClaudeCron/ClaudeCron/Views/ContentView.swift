import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @State private var selectedTask: ClaudeTask?
    @State private var selectedRun: TaskRun?
    @State private var showingNewTask = false
    @State private var showingSettings = false
    @State private var editingTask: ClaudeTask?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            TaskListView(
                selectedTask: $selectedTask,
                showingNewTask: $showingNewTask,
                showingSettings: $showingSettings
            )
            .frame(minWidth: 220)
        } content: {
            if showingSettings {
                SettingsView(onClose: { showingSettings = false })
            } else if showingNewTask || editingTask != nil {
                TaskFormView(
                    editingTask: editingTask,
                    onSave: { task in
                        if editingTask != nil {
                            // Editing existing task — just save and reinstall
                            try? modelContext.save()
                            LaunchdService.shared.install(task: task)
                            editingTask = nil
                        } else {
                            // Creating new task
                            modelContext.insert(task)
                            try? modelContext.save()
                            LaunchdService.shared.install(task: task)
                            selectedTask = task
                            showingNewTask = false
                        }
                    },
                    onCancel: {
                        editingTask = nil
                        showingNewTask = false
                    }
                )
                .frame(minWidth: 350)
            } else if let task = selectedTask {
                TaskDetailView(task: task, selectedRun: $selectedRun, onEdit: { task in
                    editingTask = task
                })
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
