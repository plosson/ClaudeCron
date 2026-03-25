import SwiftUI

struct TaskFormView: View {
    @Environment(FolderRegistry.self) private var folderRegistry
    @State private var name = ""
    @State private var prompt = ""
    @State private var directory = ""
    @State private var model: ClaudeModel = .sonnet
    @State private var permissionMode: PermissionMode = .default_
    @State private var scheduleType: ScheduleType = .manual
    @State private var scheduleTime = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State private var selectedWeekdays: Set<Int> = []
    @State private var intervalMinutes = 60
    @State private var sessionMode: SessionMode = .new
    @State private var sessionId = ""
    @State private var allowedTools = ""
    @State private var disallowedTools = ""
    @State private var notifyOnStart = false
    @State private var notifyOnEnd = true
    @State private var showAdvanced = false
    @State private var useExistingCommand = false
    @State private var selectedScope: String = ""
    @State private var conflictWarning: String?

    var editingTask: ClaudeTask?
    var onSave: (ClaudeTask) -> Void
    var onCancel: () -> Void

    private var isEditing: Bool { editingTask != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || (prompt.isEmpty && !useExistingCommand) || directory.isEmpty || conflictWarning != nil)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Task Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Task Name").font(.subheadline.bold())
                        TextField("e.g., Daily Report", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Scope
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scope").font(.subheadline.bold())
                        Picker("", selection: $selectedScope) {
                            Text("Global").tag("")
                            ForEach(folderRegistry.folders, id: \.self) { folder in
                                Text((folder as NSString).lastPathComponent).tag(folder)
                            }
                        }
                        if selectedScope.isEmpty {
                            Text("Task saved in ~/.ccron/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Task saved in \((selectedScope as NSString).lastPathComponent)/.ccron/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let warning = conflictWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Prompt type toggle
                    Picker("", selection: $useExistingCommand) {
                        Text("Claude Prompt").tag(false)
                        Text("Existing Command").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useExistingCommand {
                        TextField("e.g., /summarize", text: $prompt)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                            .border(.secondary.opacity(0.3))
                    }

                    // Working Directory
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Working Directory").font(.subheadline.bold())
                        HStack {
                            TextField("/path/to/project", text: $directory)
                                .textFieldStyle(.roundedBorder)
                            Button(action: browseDirectory) {
                                Image(systemName: "folder")
                            }
                        }
                    }

                    // Model + Permissions side by side
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model").font(.subheadline.bold())
                            Picker("", selection: $model) {
                                ForEach(ClaudeModel.allCases, id: \.self) { m in
                                    Text(m.rawValue.capitalized).tag(m)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permissions").font(.subheadline.bold())
                            Picker("", selection: $permissionMode) {
                                Text("Default").tag(PermissionMode.default_)
                                Text("Bypass").tag(PermissionMode.bypass)
                                Text("Plan").tag(PermissionMode.plan)
                                Text("Accept Edits").tag(PermissionMode.acceptEdits)
                            }
                        }
                    }

                    // Schedule
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schedule").font(.subheadline.bold())
                        Picker("", selection: $scheduleType) {
                            ForEach(ScheduleType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }

                        if scheduleType == .daily || scheduleType == .weekly || scheduleType == .monthly {
                            DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        }

                        if scheduleType == .weekly {
                            WeekdayPicker(selection: $selectedWeekdays)
                        }

                        if scheduleType == .interval {
                            Stepper("Every \(intervalMinutes) minutes", value: $intervalMinutes, in: 1...1440, step: 15)
                        }
                    }

                    // Advanced Options
                    DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Session").font(.subheadline.bold())
                                Picker("", selection: $sessionMode) {
                                    ForEach(SessionMode.allCases, id: \.self) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                            }
                            if sessionMode != .new {
                                TextField("Session ID", text: $sessionId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            TextField("Allowed Tools (comma-separated)", text: $allowedTools)
                                .textFieldStyle(.roundedBorder)
                            TextField("Disallowed Tools (comma-separated)", text: $disallowedTools)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Notifications
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications").font(.subheadline.bold())
                        HStack {
                            Toggle("Task Start", isOn: $notifyOnStart)
                                .toggleStyle(.checkbox)
                            Toggle("Task End", isOn: $notifyOnEnd)
                                .toggleStyle(.checkbox)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { populateFromEditingTask() }
        .onChange(of: selectedScope) { oldValue, newValue in
            if !newValue.isEmpty {
                if directory.isEmpty || directory == oldValue {
                    directory = newValue
                }
            }
            validateConflict()
        }
        .onChange(of: name) { _, _ in
            validateConflict()
        }
    }

    private func populateFromEditingTask() {
        guard let task = editingTask else { return }
        name = task.name
        prompt = task.prompt
        directory = task.directory
        model = ClaudeModel(rawValue: task.model) ?? .sonnet
        permissionMode = PermissionMode(rawValue: task.permissionMode) ?? .default_
        useExistingCommand = task.prompt.hasPrefix("/")
        let schedule = task.schedule
        scheduleType = schedule.type
        scheduleTime = schedule.time
        selectedWeekdays = schedule.weekdays
        intervalMinutes = schedule.intervalMinutes
        sessionMode = SessionMode(rawValue: task.sessionMode) ?? .new
        sessionId = task.sessionId ?? ""
        allowedTools = task.allowedTools
        disallowedTools = task.disallowedTools
        notifyOnStart = task.notifyOnStart
        notifyOnEnd = task.notifyOnEnd
        selectedScope = task.sourceFolder == NSHomeDirectory() ? "" : task.sourceFolder
    }

    private func save() {
        let schedule = TaskSchedule(
            type: scheduleType,
            time: scheduleTime,
            weekdays: selectedWeekdays,
            intervalMinutes: intervalMinutes
        )

        if let task = editingTask {
            task.name = name
            task.prompt = prompt
            task.directory = directory
            task.model = model.rawValue
            task.permissionMode = permissionMode.rawValue
            task.schedule = schedule
            task.sessionMode = sessionMode.rawValue
            task.allowedTools = allowedTools
            task.disallowedTools = disallowedTools
            task.notifyOnStart = notifyOnStart
            task.notifyOnEnd = notifyOnEnd
            if sessionMode != .new && !sessionId.isEmpty {
                task.sessionId = sessionId
            } else if sessionMode == .new {
                task.sessionId = nil
            }
            task.sourceFolder = selectedScope.isEmpty ? NSHomeDirectory() : selectedScope
            onSave(task)
        } else {
            let task = ClaudeTask(
                name: name,
                prompt: prompt,
                directory: directory,
                model: model,
                permissionMode: permissionMode,
                schedule: schedule,
                sessionMode: sessionMode,
                allowedTools: allowedTools,
                disallowedTools: disallowedTools,
                notifyOnStart: notifyOnStart,
                notifyOnEnd: notifyOnEnd
            )
            if sessionMode != .new && !sessionId.isEmpty {
                task.sessionId = sessionId
            }
            task.sourceFolder = selectedScope.isEmpty ? NSHomeDirectory() : selectedScope
            task.taskId = name.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            if task.taskId.isEmpty { task.taskId = UUID().uuidString }
            onSave(task)
        }
    }

    private func validateConflict() {
        let folder = selectedScope.isEmpty ? NSHomeDirectory() : selectedScope
        let candidateId = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        guard !candidateId.isEmpty else {
            conflictWarning = nil
            return
        }

        // Don't warn about conflict with self when editing
        if let editing = editingTask,
           editing.sourceFolder == folder && editing.taskId == candidateId {
            conflictWarning = nil
            return
        }

        let settings = ConfigService.shared.read(folder: folder)
        if settings.tasks[candidateId] != nil {
            let scopeName = selectedScope.isEmpty ? "Global" : (selectedScope as NSString).lastPathComponent
            conflictWarning = "A task '\(candidateId)' already exists in \(scopeName)"
        } else {
            conflictWarning = nil
        }
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            directory = url.path
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                Toggle(days[day - 1], isOn: Binding(
                    get: { selection.contains(day) },
                    set: { isOn in
                        if isOn { selection.insert(day) }
                        else { selection.remove(day) }
                    }
                ))
                .toggleStyle(.button)
                .buttonStyle(.bordered)
            }
        }
    }
}
