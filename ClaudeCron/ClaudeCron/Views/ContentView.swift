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
    @Environment(FolderRegistry.self) private var folderRegistry

    var body: some View {
        NavigationSplitView {
            TaskListView(
                selectedTask: $selectedTask,
                showingNewTask: $showingNewTask,
                showingSettings: $showingSettings,
                onAddFolder: addFolder
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
            // Import tasks from all registered folders on launch
            for folder in folderRegistry.allFolders {
                importFolder(folder)
            }
            LaunchdService.shared.syncAll(modelContext: modelContext)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder containing .ccron/settings.json"
        if panel.runModal() == .OK, let url = panel.url {
            importFolder(url.path)
        }
    }

    private func importFolder(_ folderPath: String) {
        let isGlobal = folderPath == NSHomeDirectory()

        folderRegistry.add(folderPath)
        let settings = ConfigService.shared.read(folder: folderPath)

        for (taskId, definition) in settings.tasks {
            let resolvedPath = isGlobal ? (definition.path ?? folderPath) : folderPath

            // Check if task already exists by composite key
            let descriptor = FetchDescriptor<ClaudeTask>(
                predicate: #Predicate { task in
                    task.sourceFolder == folderPath && task.taskId == taskId
                }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.update(from: definition, resolvedPath: resolvedPath)
            } else {
                let task = ClaudeTask()
                task.taskId = taskId
                task.sourceFolder = folderPath
                task.update(from: definition, resolvedPath: resolvedPath)
                modelContext.insert(task)
            }
        }

        try? modelContext.save()

        // Install launchd jobs for imported tasks
        let allDescriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { task in
                task.sourceFolder == folderPath
            }
        )
        if let tasks = try? modelContext.fetch(allDescriptor) {
            for task in tasks {
                LaunchdService.shared.install(task: task)
            }
        }
    }
}
