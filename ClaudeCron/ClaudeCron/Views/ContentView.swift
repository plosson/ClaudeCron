import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @State private var selectedTask: ClaudeTask?
    @State private var selectedRun: TaskRun?
    @State private var showingNewTask = false
    @State private var showingSettings = false
    @State private var editingTask: ClaudeTask?
    @State private var editingOriginalFolder: String = ""
    @State private var editingOriginalTaskId: String = ""
    @Environment(\.modelContext) private var modelContext
    @Environment(FolderRegistry.self) private var folderRegistry

    var body: some View {
        NavigationSplitView {
            TaskListView(
                selectedTask: $selectedTask,
                showingNewTask: $showingNewTask,
                showingSettings: $showingSettings,
                onAddFolder: addFolder,
                onResync: resyncAll,
                onRemoveFolder: removeFolder
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
                            // Editing existing task — save and reinstall
                            try? modelContext.save()
                            LaunchdService.shared.install(task: task)

                            // If scope or taskId changed, remove from old location
                            if (editingOriginalFolder != task.sourceFolder || editingOriginalTaskId != task.taskId)
                               && !editingOriginalFolder.isEmpty {
                                var oldSettings = ConfigService.shared.read(folder: editingOriginalFolder)
                                oldSettings.tasks.removeValue(forKey: editingOriginalTaskId)
                                try? ConfigService.shared.write(oldSettings, to: editingOriginalFolder)
                            }

                            persistToJSON(task: task)
                            editingTask = nil
                        } else {
                            // Creating new task — sourceFolder and taskId already set by form
                            // Register folder if local scope
                            if task.sourceFolder != NSHomeDirectory() {
                                folderRegistry.add(task.sourceFolder)
                            }
                            modelContext.insert(task)
                            try? modelContext.save()
                            LaunchdService.shared.install(task: task)
                            persistToJSON(task: task)
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
                    editingOriginalFolder = task.sourceFolder
                    editingOriginalTaskId = task.taskId
                    editingTask = task
                }, onDelete: { task in
                    removeFromJSON(task: task)
                    selectedTask = nil
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
            resyncAll()
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

    private func persistToJSON(task: ClaudeTask) {
        let folder = task.sourceFolder
        guard !folder.isEmpty else { return }
        let isGlobal = folder == NSHomeDirectory()
        var settings = ConfigService.shared.read(folder: folder)
        settings.tasks[task.taskId] = task.toTaskDefinition(isGlobal: isGlobal)
        try? ConfigService.shared.write(settings, to: folder)
    }

    private func removeFromJSON(task: ClaudeTask) {
        let folder = task.sourceFolder
        guard !folder.isEmpty else { return }
        var settings = ConfigService.shared.read(folder: folder)
        settings.tasks.removeValue(forKey: task.taskId)
        try? ConfigService.shared.write(settings, to: folder)
    }

    private func resyncAll() {
        for folder in folderRegistry.allFolders {
            importFolder(folder)
        }

        // Remove tasks whose taskId no longer exists in their source settings file
        let descriptor = FetchDescriptor<ClaudeTask>()
        guard let allTasks = try? modelContext.fetch(descriptor) else { return }

        for task in allTasks {
            guard !task.sourceFolder.isEmpty else { continue }
            let settings = ConfigService.shared.read(folder: task.sourceFolder)
            if settings.tasks[task.taskId] == nil {
                LaunchdService.shared.uninstall(task: task)
                modelContext.delete(task)
            }
        }
        try? modelContext.save()
    }

    private func removeFolder(_ folder: String) {
        // Delete all tasks from this folder
        let descriptor = FetchDescriptor<ClaudeTask>(
            predicate: #Predicate { task in
                task.sourceFolder == folder
            }
        )
        if let tasks = try? modelContext.fetch(descriptor) {
            for task in tasks {
                LaunchdService.shared.uninstall(task: task)
                modelContext.delete(task)
            }
        }
        try? modelContext.save()
        folderRegistry.remove(folder)
        selectedTask = nil
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
