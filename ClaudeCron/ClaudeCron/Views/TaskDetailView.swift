import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: ClaudeTask
    @Binding var selectedRun: TaskRun?
    @Environment(\.modelContext) private var modelContext

    var sortedRuns: [TaskRun] {
        task.runs.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header toolbar
            HStack {
                Button(action: { LaunchdService.shared.triggerNow(task: task, modelContext: modelContext) }) {
                    Image(systemName: "play.circle")
                }
                .help("Run Now")

                Button(action: { /* TODO: edit */ }) {
                    Image(systemName: "pencil.circle")
                }
                .help("Edit")

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

            Spacer()
        }
    }

    private func deleteTask() {
        modelContext.delete(task)
        try? modelContext.save()
    }
}
