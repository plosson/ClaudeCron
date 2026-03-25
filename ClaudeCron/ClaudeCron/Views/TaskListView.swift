import SwiftUI
import SwiftData

struct TaskListView: View {
    @Query(sort: \ClaudeTask.createdAt, order: .reverse) private var tasks: [ClaudeTask]
    @Binding var selectedTask: ClaudeTask?
    @Binding var showingNewTask: Bool
    @Binding var showingSettings: Bool
    var onAddFolder: () -> Void
    var onResync: () -> Void
    var onRemoveFolder: (String) -> Void

    var tasksByFolder: [(String, [ClaudeTask])] {
        let grouped = Dictionary(grouping: tasks) { $0.sourceFolder }
        return grouped.sorted { $0.key < $1.key }
    }

    private var hasSingleFolder: Bool {
        tasksByFolder.count <= 1
    }

    private func displayName(for folder: String) -> String {
        if folder == NSHomeDirectory() { return "Global" }
        let name = (folder as NSString).lastPathComponent
        return name.isEmpty ? "Unsorted" : name
    }

    var body: some View {
        List(selection: $selectedTask) {
            ForEach(tasksByFolder, id: \.0) { folder, folderTasks in
                if hasSingleFolder {
                    ForEach(folderTasks) { task in
                        TaskRowView(task: task)
                            .tag(task)
                    }
                } else {
                    Section {
                        ForEach(folderTasks) { task in
                            TaskRowView(task: task)
                                .tag(task)
                        }
                    } header: {
                        HStack {
                            Text(displayName(for: folder))
                            Spacer()
                            if folder != NSHomeDirectory() {
                                Button(action: { onRemoveFolder(folder) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove folder")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { showingNewTask = true }) {
                        Label("New Task", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Button(action: onAddFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                    .help("Settings")
                    Spacer()
                    Button(action: onResync) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Resync folders")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
