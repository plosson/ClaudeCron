import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Query(sort: \ClaudeTask.createdAt, order: .reverse) private var tasks: [ClaudeTask]
    @State private var selectedTask: ClaudeTask?
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

    @State private var showRuns = false

    private struct TaskGroup {
        let folder: String
        let displayName: String
        let tasks: [ClaudeTask]
    }

    private var groupedTasks: [TaskGroup] {
        let grouped = Dictionary(grouping: tasks) { $0.sourceFolder }
        return grouped.keys.sorted().map { folder in
            let name: String
            if folder == NSHomeDirectory() {
                name = "Global"
            } else {
                name = (folder as NSString).lastPathComponent
            }
            return TaskGroup(folder: folder, displayName: name, tasks: grouped[folder]!)
        }
    }

    @ViewBuilder
    private func taskCard(for task: ClaudeTask) -> some View {
        TaskCardView(task: task)
            .onTapGesture {
                showRuns = !task.runs.isEmpty
                selectedTask = task
            }
            .contextMenu {
                Button("Run Now") {
                    LaunchdService.shared.triggerNow(task: task, modelContext: modelContext)
                }
                .disabled(task.runs.contains { $0.runStatus == .running })
                Divider()
                Button("Delete", role: .destructive) {
                    removeFromJSON(task: task)
                    LaunchdService.shared.uninstall(task: task)
                    modelContext.delete(task)
                    try? modelContext.save()
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let task = selectedTask {
                // DETAIL VIEW — full screen drill-down
                VStack(spacing: 0) {
                    // Back bar
                    HStack(spacing: 8) {
                        Button(action: {
                            selectedTask = nil
                            showRuns = false
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Tasks")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Back to tasks (Esc)")

                        Spacer()

                        Text(task.name)
                            .font(.headline)

                        Spacer()

                        Color.clear.frame(width: 60, height: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()

                    if showRuns {
                        HSplitView {
                            TaskDetailView(
                                task: task,
                                showRuns: $showRuns,
                                onDelete: { t in
                                    removeFromJSON(task: t)
                                    selectedTask = nil
                                }
                            )
                            .frame(minWidth: 250, idealWidth: 350)

                            RunDetailView(task: task, showRuns: $showRuns)
                                .frame(minWidth: 400)
                        }
                    } else {
                        TaskDetailView(
                            task: task,
                            showRuns: $showRuns,
                            onDelete: { t in
                                removeFromJSON(task: t)
                                selectedTask = nil
                            }
                        )
                    }
                }
                .onChange(of: selectedTask) { _, newTask in
                    showRuns = !(newTask?.runs.isEmpty ?? true)
                }
            } else {
                // HOME VIEW — full-width card grid
                VStack(spacing: 0) {
                    // Top bar
                    HStack(spacing: 12) {
                        Text("Claude Cron")
                            .font(.title2.bold())

                        Spacer()

                        HStack(spacing: 8) {
                            StatusPill(count: okCount, label: "OK", color: .green)
                            StatusPill(count: runningCount, label: "Running", color: .blue)
                            StatusPill(count: failedCount, label: "Failed", color: .red)
                        }

                        Spacer()

                        SettingsLink {
                            Image(systemName: "gear")
                        }
                        .help("Settings")

                        Menu {
                            Button(action: createNewTask) {
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
                                .foregroundStyle(.purple)
                        }
                        .help("Create")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    Divider()

                    if tasks.isEmpty {
                        ContentUnavailableView("No Tasks", systemImage: "clock.badge.questionmark", description: Text("Click + to create a new task or add a folder."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(groupedTasks, id: \.folder) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)

                                        LazyVGrid(columns: gridColumns, spacing: 16) {
                                            ForEach(group.tasks) { task in
                                                taskCard(for: task)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            resyncAll()
            if !cliPromptDismissed && !CLIInstallService.isInstalled {
                showingCLIPrompt = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTaskShortcut)) { _ in
            createNewTask()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backToTasksShortcut)) { _ in
            selectedTask = nil
            showRuns = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .runTaskShortcut)) { _ in
            guard let task = selectedTask else { return }
            if !task.runs.contains(where: { $0.runStatus == .running }) {
                LaunchdService.shared.triggerNow(task: task, modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTaskShortcut)) { _ in
            guard let task = selectedTask else { return }
            task.isEnabled.toggle()
            do { try modelContext.save() } catch {}
            LaunchdService.shared.install(task: task)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteTaskShortcut)) { _ in
            guard let task = selectedTask else { return }
            removeFromJSON(task: task)
            LaunchdService.shared.uninstall(task: task)
            modelContext.delete(task)
            try? modelContext.save()
            selectedTask = nil
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

    private func createNewTask() {
        let task = ClaudeTask()
        task.sourceFolder = NSHomeDirectory()
        modelContext.insert(task)
        showRuns = false
        selectedTask = task
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
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [color.opacity(0.12), color.opacity(0.06)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
    }
}

