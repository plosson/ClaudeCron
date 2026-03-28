import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: ClaudeTask
    @Binding var showRuns: Bool
    var onDelete: (ClaudeTask) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext

    @State private var promptSource: PromptSource = .inline
    @State private var promptText = ""
    @State private var promptFile = ""
    @State private var showAdvanced = false
    @State private var statusMessage: String?
    @State private var isLocalScope = false
    @State private var showAvatarPicker = false

    enum PromptSource: String, CaseIterable {
        case inline = "Inline"
        case file = "File"
        case command = "Command"
    }

    private var scheduleBinding: Binding<TaskSchedule> {
        Binding(
            get: { task.schedule },
            set: { task.schedule = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                if let runningRun = task.runs.first(where: { $0.runStatus == .running }) {
                    Button(action: { LaunchdService.shared.cancelRun(runningRun, modelContext: modelContext) }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .help("Stop running task")
                } else {
                    Button(action: { LaunchdService.shared.triggerNow(task: task, modelContext: modelContext) }) {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .controlSize(.small)
                    .help("Run task now (Cmd+R)")
                }

                Toggle(isOn: $task.isEnabled) {
                    Image(systemName: task.isEnabled ? "bolt.fill" : "bolt.slash")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Toggle enabled (Cmd+E)")
                .onChange(of: task.isEnabled) { _, _ in
                    do { try modelContext.save() } catch {}
                    LaunchdService.shared.install(task: task)
                    persistToJSON()
                }

                Button(action: { showRuns.toggle() }) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(showRuns ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Runs")

                Spacer()

                Button("Save") { saveTask() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Save changes (Cmd+S)")

                Button(action: deleteTask) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete task (Cmd+Delete)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Form
            ScrollView {
                VStack(spacing: 12) {

                    // ── 1. What ──
                    FormSection("What", icon: "text.quote") {
                        HStack(alignment: .top, spacing: 12) {
                            PixelAvatarView(config: task.avatarConfig, pixelSize: 4)
                                .onTapGesture { showAvatarPicker = true }
                                .popover(isPresented: $showAvatarPicker) {
                                    AvatarPickerView(
                                        config: Binding(
                                            get: { task.avatarConfig },
                                            set: { task.avatarConfig = $0 }
                                        ),
                                        onReset: {
                                            task.avatarConfigData = nil
                                        }
                                    )
                                }
                                .help("Click to customize avatar")

                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Task name", text: $task.name)
                                    .font(.title3.bold())
                                    .textFieldStyle(.plain)

                                FormField("Description") {
                                    HStack(alignment: .top, spacing: 6) {
                                        TextEditor(text: $task.taskDescription)
                                            .font(.body)
                                            .frame(height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(.secondary.opacity(0.2))
                                            )
                                        Button(action: generateDescription) {
                                            if statusMessage != nil {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Image(systemName: "wand.and.stars")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.cyan)
                                        .controlSize(.small)
                                        .disabled(statusMessage != nil)
                                        .help("Generate with AI")
                                    }
                                }
                            }
                        }
                    }

                    // ── 2. Where & How ──
                    FormSection("Where & How", icon: "terminal") {
                        FormField("Working Directory") {
                            HStack(spacing: 6) {
                                TextField("/path/to/project", text: $task.directory)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: browseDirectory) {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Browse for directory")
                            }
                        }

                        FormField("Scope") {
                            Picker("", selection: $isLocalScope) {
                                Text("Global").tag(false)
                                Text("Local").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)

                            if isLocalScope {
                                if task.directory.isEmpty {
                                    Text("Set a working directory first")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Saved in \(task.directory)/.ccron/settings.json")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Saved in ~/.ccron/settings.json")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Prompt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: $promptSource) {
                                    ForEach(PromptSource.allCases, id: \.self) { s in
                                        Text(s.rawValue).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            switch promptSource {
                            case .inline:
                                TextEditor(text: $promptText)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 80, maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(.secondary.opacity(0.2))
                                    )
                            case .file:
                                HStack(spacing: 6) {
                                    TextField("path/to/prompt.md", text: $promptFile)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: browsePromptFile) {
                                        Image(systemName: "doc")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Browse for prompt file")
                                }
                                if !promptFile.isEmpty && !task.directory.isEmpty {
                                    let fullPath = URL(fileURLWithPath: task.directory).appendingPathComponent(promptFile).path
                                    HStack(spacing: 4) {
                                        Image(systemName: FileManager.default.fileExists(atPath: fullPath) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.caption)
                                        Text(FileManager.default.fileExists(atPath: fullPath) ? "File found" : "File not found")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(FileManager.default.fileExists(atPath: fullPath) ? .green : .red)
                                }
                            case .command:
                                TextField("e.g., /summarize", text: $promptText)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    // ── 3. When ──
                    FormSection("Schedule", icon: "calendar.badge.clock") {
                        Picker("", selection: scheduleBinding.type) {
                            ForEach(ScheduleType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        if [.daily, .weekly, .monthly].contains(task.schedule.type) {
                            DatePicker("Time", selection: scheduleBinding.time, displayedComponents: .hourAndMinute)
                        }

                        if task.schedule.type == .weekly {
                            WeekdayPicker(selection: scheduleBinding.weekdays)
                        }

                        if task.schedule.type == .interval {
                            Stepper("Every \(task.schedule.intervalMinutes) min",
                                    value: scheduleBinding.intervalMinutes, in: 1...1440, step: 15)
                        }
                    }

                    // ── 4. Settings ──
                    FormSection("Settings", icon: "gearshape") {
                        HStack(spacing: 16) {
                            Toggle("Notify on start", isOn: $task.notifyOnStart)
                                .toggleStyle(.checkbox)
                            Toggle("Notify on completion", isOn: $task.notifyOnEnd)
                                .toggleStyle(.checkbox)
                        }

                        DisclosureGroup(isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 16) {
                                    FormField("Model") {
                                        Picker("", selection: $task.model) {
                                            ForEach(ClaudeModel.allCases, id: \.self) { m in
                                                Text(m.rawValue.capitalized).tag(m.rawValue)
                                            }
                                        }
                                        .labelsHidden()
                                    }

                                    FormField("Permissions") {
                                        Picker("", selection: $task.permissionMode) {
                                            Text("Default").tag(PermissionMode.default_.rawValue)
                                            Text("Bypass").tag(PermissionMode.bypass.rawValue)
                                            Text("Plan").tag(PermissionMode.plan.rawValue)
                                            Text("Accept Edits").tag(PermissionMode.acceptEdits.rawValue)
                                        }
                                        .labelsHidden()
                                    }
                                }

                                HStack(spacing: 16) {
                                    FormField("Session") {
                                        Picker("", selection: Binding(
                                            get: { SessionMode(rawValue: task.sessionMode) ?? .new },
                                            set: { task.sessionMode = $0.rawValue }
                                        )) {
                                            ForEach(SessionMode.allCases, id: \.self) { m in
                                                Text(m.rawValue).tag(m)
                                            }
                                        }
                                        .labelsHidden()
                                    }

                                    if task.sessionMode != SessionMode.new.rawValue {
                                        FormField("Session ID") {
                                            TextField("", text: Binding(
                                                get: { task.sessionId ?? "" },
                                                set: { task.sessionId = $0.isEmpty ? nil : $0 }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                        }
                                    }
                                }

                                FormField("Allowed Tools") {
                                    TextField("comma-separated", text: $task.allowedTools)
                                        .textFieldStyle(.roundedBorder)
                                }

                                FormField("Disallowed Tools") {
                                    TextField("comma-separated", text: $task.disallowedTools)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Advanced")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            // Status bar
            if let statusMessage {
                Divider()
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .onAppear { loadPromptState() }
        .onReceive(NotificationCenter.default.publisher(for: .saveTaskShortcut)) { _ in
            saveTask()
        }
    }

    private func loadPromptState() {
        promptFile = task.promptFile
        promptText = task.prompt
        isLocalScope = !task.sourceFolder.isEmpty && task.sourceFolder != NSHomeDirectory()
        if !task.promptFile.isEmpty {
            promptSource = .file
        } else if task.prompt.hasPrefix("/") {
            promptSource = .command
        } else {
            promptSource = .inline
        }
    }

    private func generateDescription() {
        // Use the current prompt text, not the saved one
        let prompt: String
        switch promptSource {
        case .inline, .command: prompt = promptText
        case .file:
            if !promptFile.isEmpty && !task.directory.isEmpty {
                let url = URL(fileURLWithPath: task.directory).appendingPathComponent(promptFile)
                prompt = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            } else {
                prompt = ""
            }
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "No prompt to summarize"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                statusMessage = nil
            }
            return
        }
        guard ClaudeService.shared.claudePath() != nil else {
            statusMessage = "Claude CLI not found"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                statusMessage = nil
            }
            return
        }

        statusMessage = "Generating description..."
        ClaudeService.shared.summarizePrompt(prompt) { summary in
            Task { @MainActor in
                if let summary {
                    task.taskDescription = summary
                }
                statusMessage = nil
            }
        }
    }

    private func saveTask() {
        switch promptSource {
        case .inline, .command:
            task.prompt = promptText
            task.promptFile = ""
        case .file:
            task.prompt = ""
            task.promptFile = promptFile
        }

        // Generate taskId from name if not yet set (new task)
        if task.taskId.isEmpty {
            task.taskId = task.name.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            if task.taskId.isEmpty { task.taskId = UUID().uuidString }
        }

        // Update sourceFolder based on scope
        task.sourceFolder = isLocalScope ? task.directory : NSHomeDirectory()

        do { try modelContext.save() } catch {
            print("[ClaudeCron] Failed to save: \(error.localizedDescription)")
        }
        LaunchdService.shared.install(task: task)
        persistToJSON()
    }

    private func toggleEnabled() {
        task.isEnabled.toggle()
        do { try modelContext.save() } catch {
            print("[ClaudeCron] Failed to save: \(error.localizedDescription)")
        }
        LaunchdService.shared.install(task: task)
        persistToJSON()
    }

    private func deleteTask() {
        let taskToDelete = task
        LaunchdService.shared.uninstall(task: taskToDelete)
        onDelete(taskToDelete)
        modelContext.delete(taskToDelete)
        do { try modelContext.save() } catch {
            print("[ClaudeCron] Failed to save: \(error.localizedDescription)")
        }
    }

    private func persistToJSON() {
        let folder = task.sourceFolder
        guard !folder.isEmpty else { return }
        let isGlobal = folder == NSHomeDirectory()
        var settings = ConfigService.shared.read(folder: folder)
        settings.tasks[task.taskId] = task.toTaskDefinition(isGlobal: isGlobal)
        do {
            try ConfigService.shared.write(settings, to: folder)
        } catch {
            print("[ClaudeCron] Failed to persist: \(error.localizedDescription)")
        }
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            task.directory = url.path
        }
    }

    private func browsePromptFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if !task.directory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: task.directory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            let dir = task.directory
            if !dir.isEmpty, url.path.hasPrefix(dir) {
                let relative = String(url.path.dropFirst(dir.count).drop(while: { $0 == "/" }))
                if !relative.isEmpty {
                    promptFile = relative
                    return
                }
            }
            promptFile = url.path
        }
    }
}

// MARK: - Section header

struct FormSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(title.uppercased())
                    .font(.caption.bold())
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.secondary.opacity(0.12))
        )
    }
}

// MARK: - Reusable form field with label

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - Run row

struct RunRowView: View {
    let run: TaskRun

    private var statusIcon: String {
        switch run.runStatus {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "circle.dotted"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch run.runStatus {
        case .succeeded: return .green
        case .failed: return .red
        case .running: return .blue
        case .cancelled: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.caption)

            Text(run.startedAt, format: .dateTime.month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(run.runStatus.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(statusColor)
            if let d = run.duration {
                Text("\(Int(d))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
