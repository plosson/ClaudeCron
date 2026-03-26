import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: ClaudeTask
    @Binding var selectedRun: TaskRun?
    var onEdit: (ClaudeTask) -> Void = { _ in }
    var onDelete: (ClaudeTask) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext

    var sortedRuns: [TaskRun] {
        task.runs.sorted { $0.startedAt > $1.startedAt }
    }

    var upcomingRuns: [Date] {
        ScheduleCalculator.nextRuns(for: task.schedule, count: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header toolbar
            HStack {
                Button(action: { LaunchdService.shared.triggerNow(task: task, modelContext: modelContext) }) {
                    Image(systemName: "play.circle")
                }
                .help("Run Now")
                .disabled(task.runs.contains { $0.runStatus == .running })

                Button(action: { onEdit(task) }) {
                    Image(systemName: "pencil.circle")
                }
                .help("Edit")

                Button(action: toggleEnabled) {
                    Image(systemName: task.isEnabled ? "pause.circle" : "play.circle.fill")
                }
                .help(task.isEnabled ? "Disable" : "Enable")

                Spacer()

                Button(role: .destructive, action: deleteTask) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider().padding(.vertical, 4)

            // Task info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.name)
                        .font(.title2.bold())
                    Text(task.model)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    if task.isEnabled {
                        Text("Enabled")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(task.schedule.displaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Command block
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.prompt.hasPrefix("/") ? "COMMAND" : "PROMPT")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(task.prompt)
                                .font(.system(.body, design: .monospaced))
                        }
                        Spacer()
                        Text(task.directory)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if task.notifyOnStart || task.notifyOnEnd {
                    HStack {
                        Text("Notifications:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if task.notifyOnStart { Text("Task Start").font(.caption) }
                        if task.notifyOnStart && task.notifyOnEnd { Text("·").font(.caption).foregroundStyle(.secondary) }
                        if task.notifyOnEnd { Text("Task End").font(.caption) }
                    }
                }
            }
            .padding(.horizontal)

            Divider().padding(.vertical, 4)

            // Runs list
            List(selection: $selectedRun) {
                if !upcomingRuns.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingRuns, id: \.self) { date in
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(date, format: .dateTime.month().day().hour().minute())
                                Spacer()
                                Text("UPCOMING")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Completed") {
                    ForEach(sortedRuns) { run in
                        RunRowView(run: run)
                            .tag(run)
                    }
                }
            }
        }
    }

    private func toggleEnabled() {
        task.isEnabled.toggle()
        do {
            try modelContext.save()
        } catch {
            print("[ClaudeCron] Failed to save context on toggle: \(error.localizedDescription)")
        }
        LaunchdService.shared.install(task: task)
        persistToJSON()
    }

    private func deleteTask() {
        let taskToDelete = task
        LaunchdService.shared.uninstall(task: taskToDelete)
        onDelete(taskToDelete)
        modelContext.delete(taskToDelete)
        do {
            try modelContext.save()
        } catch {
            print("[ClaudeCron] Failed to save context on delete: \(error.localizedDescription)")
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
            print("[ClaudeCron] Failed to persist task to JSON: \(error.localizedDescription)")
        }
    }
}

struct RunRowView: View {
    let run: TaskRun

    var body: some View {
        HStack {
            Text(run.task?.name ?? "")
            Text(run.startedAt, format: .dateTime.month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(run.runStatus.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(run.runStatus == .succeeded ? .green : run.runStatus == .failed ? .red : .blue)
            if let d = run.duration {
                Text("Duration: \(Int(d))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
