import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Query(sort: \ClaudeTask.createdAt, order: .reverse) private var tasks: [ClaudeTask]
    @State private var selectedTask: ClaudeTask?
    @State private var showingNewTask = false
    @State private var showingSettings = false
    @State private var editingTask: ClaudeTask?
    @State private var editingOriginalFolder: String = ""
    @State private var editingOriginalTaskId: String = ""
    @State private var showingCLIPrompt = false
    @AppStorage("cliPromptDismissed") private var cliPromptDismissed = false
    @Environment(\.modelContext) private var modelContext
    @Environment(FolderRegistry.self) private var folderRegistry

    private var okCount: Int {
        tasks.filter { task in
            task.isEnabled && !task.runs.contains { $0.runStatus == .running }
            && (task.runs.sorted { $0.startedAt > $1.startedAt }.first?.runStatus != .failed)
        }.count
    }

    private var runningCount: Int {
        tasks.filter { task in task.runs.contains { $0.runStatus == .running } }.count
    }

    private var failedCount: Int {
        tasks.filter { task in
            guard let latest = task.runs.sorted(by: { $0.startedAt > $1.startedAt }).first else { return false }
            return latest.runStatus == .failed
        }.count
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 280), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                Text("Claude Cron")
                    .font(.title2.bold())

                Spacer()

                // Aggregate status pills
                HStack(spacing: 8) {
                    StatusPill(count: okCount, label: "OK", color: .green)
                    StatusPill(count: runningCount, label: "Running", color: .blue)
                    StatusPill(count: failedCount, label: "Failed", color: .red)
                }

                Spacer()

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .help("Settings")

                Menu {
                    Button(action: { showingNewTask = true }) {
                        Label("New Task", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Button(action: addFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    Button(action: resyncAll) {
                        Label("Resync Folders", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Main grid
            if tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "clock.badge.questionmark", description: Text("Click + to create a new task or add a folder."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(tasks) { task in
                            TaskCardView(task: task)
                                .onTapGesture { selectedTask = task }
                                .contextMenu {
                                    Button("Run Now") {
                                        LaunchdService.shared.triggerNow(task: task, modelContext: modelContext)
                                    }
                                    .disabled(task.runs.contains { $0.runStatus == .running })
                                    Button("Edit") {
                                        editingOriginalFolder = task.sourceFolder
                                        editingOriginalTaskId = task.taskId
                                        editingTask = task
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        removeFromJSON(task: task)
                                        LaunchdService.shared.uninstall(task: task)
                                        modelContext.delete(task)
                                        try? modelContext.save()
                                    }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
        // Task detail sheet
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(
                task: task,
                onEdit: { t in
                    selectedTask = nil
                    editingOriginalFolder = t.sourceFolder
                    editingOriginalTaskId = t.taskId
                    editingTask = t
                },
                onDelete: { t in
                    removeFromJSON(task: t)
                    selectedTask = nil
                }
            )
            .frame(minWidth: 550, minHeight: 500)
        }
        // Settings sheet
        .sheet(isPresented: $showingSettings) {
            SettingsView(onClose: { showingSettings = false })
                .frame(minWidth: 420, minHeight: 350)
        }
        // New / Edit task sheet
        .sheet(isPresented: Binding(
            get: { showingNewTask || editingTask != nil },
            set: { if !$0 { showingNewTask = false; editingTask = nil } }
        )) {
            TaskFormView(
                editingTask: editingTask,
                onSave: { task in
                    if editingTask != nil {
                        do { try modelContext.save() } catch {
                            print("[ClaudeCron] Failed to save context on edit: \(error.localizedDescription)")
                        }
                        LaunchdService.shared.install(task: task)

                        if (editingOriginalFolder != task.sourceFolder || editingOriginalTaskId != task.taskId)
                           && !editingOriginalFolder.isEmpty {
                            var oldSettings = ConfigService.shared.read(folder: editingOriginalFolder)
                            oldSettings.tasks.removeValue(forKey: editingOriginalTaskId)
                            do {
                                try ConfigService.shared.write(oldSettings, to: editingOriginalFolder)
                            } catch {
                                print("[ClaudeCron] Failed to write config on task move: \(error.localizedDescription)")
                            }
                        }

                        persistToJSON(task: task)
                        editingTask = nil
                    } else {
                        if task.sourceFolder != NSHomeDirectory() {
                            folderRegistry.add(task.sourceFolder)
                        }
                        modelContext.insert(task)
                        do { try modelContext.save() } catch {
                            print("[ClaudeCron] Failed to save context on insert: \(error.localizedDescription)")
                        }
                        LaunchdService.shared.install(task: task)
                        persistToJSON(task: task)
                        showingNewTask = false
                    }
                },
                onCancel: {
                    editingTask = nil
                    showingNewTask = false
                }
            )
            .frame(minWidth: 450, minHeight: 500)
        }
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            resyncAll()
            if !cliPromptDismissed && !CLIInstallService.isInstalled {
                showingCLIPrompt = true
            }
        }
        .alert("Install Command Line Tool?", isPresented: $showingCLIPrompt) {
            Button("Install") {
                do { try CLIInstallService.install() } catch {
                    print("[ClaudeCron] Failed to install CLI tool: \(error.localizedDescription)")
                }
                cliPromptDismissed = true
            }
            Button("No Thanks", role: .cancel) {
                cliPromptDismissed = true
            }
        } message: {
            Text("Would you like to install the ccron command line tool? This lets you run tasks from your terminal.")
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
        do {
            try ConfigService.shared.write(settings, to: folder)
        } catch {
            print("[ClaudeCron] Failed to persist task to JSON: \(error.localizedDescription)")
        }
    }

    private func removeFromJSON(task: ClaudeTask) {
        let folder = task.sourceFolder
        guard !folder.isEmpty else { return }
        var settings = ConfigService.shared.read(folder: folder)
        settings.tasks.removeValue(forKey: task.taskId)
        do {
            try ConfigService.shared.write(settings, to: folder)
        } catch {
            print("[ClaudeCron] Failed to remove task from JSON: \(error.localizedDescription)")
        }
    }

    private func resyncAll() {
        for folder in folderRegistry.allFolders {
            importFolder(folder)
        }

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
        do { try modelContext.save() } catch {
            print("[ClaudeCron] Failed to save context on resync: \(error.localizedDescription)")
        }
    }

    private func importFolder(_ folderPath: String) {
        let isGlobal = folderPath == NSHomeDirectory()

        folderRegistry.add(folderPath)
        let settings = ConfigService.shared.read(folder: folderPath)

        for (taskId, definition) in settings.tasks {
            let resolvedPath = isGlobal ? (definition.path ?? folderPath) : folderPath

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

        do { try modelContext.save() } catch {
            print("[ClaudeCron] Failed to save context on folder import: \(error.localizedDescription)")
        }

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

// MARK: - Status Pill

struct StatusPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {
    @Bindable var task: ClaudeTask
    var onEdit: (ClaudeTask) -> Void
    var onDelete: (ClaudeTask) -> Void
    @State private var selectedRun: TaskRun?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header with close button
            HStack {
                Text(task.name)
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            HSplitView {
                TaskDetailView(
                    task: task,
                    selectedRun: $selectedRun,
                    onEdit: { t in
                        dismiss()
                        onEdit(t)
                    },
                    onDelete: { t in
                        dismiss()
                        onDelete(t)
                    }
                )
                .frame(minWidth: 280)

                if let run = selectedRun {
                    RunDetailView(run: run)
                        .frame(minWidth: 300)
                }
            }
        }
    }
}
