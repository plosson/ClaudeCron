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
                    .disabled(name.isEmpty || (prompt.isEmpty && !useExistingCommand) || directory.isEmpty)
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
        onSave(task)
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
