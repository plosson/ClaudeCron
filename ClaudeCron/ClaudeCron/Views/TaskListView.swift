import SwiftUI
import SwiftData

struct TaskListView: View {
    @Query(sort: \ClaudeTask.createdAt, order: .reverse) private var tasks: [ClaudeTask]
    @Binding var selectedTask: ClaudeTask?
    @Binding var showingNewTask: Bool
    @Binding var showingSettings: Bool
    var onAddFolder: () -> Void

    var body: some View {
        List(selection: $selectedTask) {
            ForEach(tasks) { task in
                TaskRowView(task: task)
                    .tag(task)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewTask = true }) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onAddFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Tasks")
    }
}

struct TaskRowView: View {
    let task: ClaudeTask

    var body: some View {
        HStack {
            Circle()
                .fill(task.isEnabled ? .green : .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                HStack {
                    Text(task.name)
                        .font(.headline)
                    Text(task.model)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(task.schedule.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
