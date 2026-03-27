import SwiftUI

struct TaskFormView: View {
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
    @State private var isLocalScope = false
    @State private var conflictWarning: String?
    @State private var promptFile = ""

    private enum PromptSource: String, CaseIterable {
        case inline = "Inline Prompt"
        case file = "Prompt File"
        case command = "Existing Command"
    }

    @State private var promptSource: PromptSource = .inline

    var onSave: (ClaudeTask) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || directory.isEmpty || conflictWarning != nil || {
                        switch promptSource {
                        case .inline, .command: return prompt.isEmpty
                        case .file: return promptFile.isEmpty
                        }
                    }())
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
                        Picker("", selection: $isLocalScope) {
                            Text("Global").tag(false)
                            Text("Local").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if isLocalScope {
                            if directory.isEmpty {
                                Text("Set a working directory to determine where settings are saved")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Task saved in \(directory)/.ccron/settings.json")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Task saved in ~/.ccron/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let warning = conflictWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Prompt source
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt").font(.subheadline.bold())
                        Picker("", selection: $promptSource) {
                            ForEach(PromptSource.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    switch promptSource {
                    case .inline:
                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                            .border(.secondary.opacity(0.3))
                    case .file:
                        HStack {
                            TextField("path/to/prompt.md", text: $promptFile)
                                .textFieldStyle(.roundedBorder)
                            Button(action: browsePromptFile) {
                                Image(systemName: "doc")
                            }
                        }
                        if !promptFile.isEmpty && !directory.isEmpty {
                            let fullPath = URL(fileURLWithPath: directory).appendingPathComponent(promptFile).path
                            if FileManager.default.fileExists(atPath: fullPath) {
                                Text("File found")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("File not found at \(fullPath)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    case .command:
                        TextField("e.g., /summarize", text: $prompt)
                            .textFieldStyle(.roundedBorder)
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
        .onChange(of: isLocalScope) { _, _ in
            validateConflict()
        }
        .onChange(of: name) { _, _ in
            validateConflict()
        }
        .onChange(of: directory) { _, _ in
            validateConflict()
        }
    }

    private func save() {
        let schedule = TaskSchedule(
            type: scheduleType,
            time: scheduleTime,
            weekdays: selectedWeekdays,
            intervalMinutes: intervalMinutes
        )

        let task = ClaudeTask(
            name: name,
            prompt: promptSource == .file ? "" : prompt,
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
        task.promptFile = promptSource == .file ? promptFile : ""
        if sessionMode != .new && !sessionId.isEmpty {
            task.sessionId = sessionId
        }
        task.sourceFolder = isLocalScope ? directory : NSHomeDirectory()
        task.taskId = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        if task.taskId.isEmpty { task.taskId = UUID().uuidString }
        onSave(task)
    }

    private func validateConflict() {
        let folder = isLocalScope ? directory : NSHomeDirectory()
        guard !folder.isEmpty else {
            conflictWarning = nil
            return
        }
        let candidateId = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        guard !candidateId.isEmpty else {
            conflictWarning = nil
            return
        }

        let settings = ConfigService.shared.read(folder: folder)
        if settings.tasks[candidateId] != nil {
            let scopeName = isLocalScope ? (directory as NSString).lastPathComponent : "Global"
            conflictWarning = "A task '\(candidateId)' already exists in \(scopeName)"
        } else {
            conflictWarning = nil
        }
    }

    private func browsePromptFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !directory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: directory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            // Store path relative to the working directory
            if !directory.isEmpty,
               let relativePath = url.path.hasPrefix(directory)
                ? String(url.path.dropFirst(directory.count).drop(while: { $0 == "/" }))
                : nil,
               !relativePath.isEmpty {
                promptFile = relativePath
            } else {
                promptFile = url.path
            }
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
