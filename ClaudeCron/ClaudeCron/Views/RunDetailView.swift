import SwiftUI

enum OutputTab: String, CaseIterable {
    case output = "Output"
    case rawOutput = "Raw Output"
    case errors = "Errors"
    case debug = "Debug"
}

struct RunDetailView: View {
    let task: ClaudeTask
    @Binding var showRuns: Bool
    @State private var selectedRun: TaskRun?
    @State private var selectedTab: OutputTab = .output
    @Environment(\.modelContext) private var modelContext
    @State private var listHeight: CGFloat = 200

    private var sortedRuns: [TaskRun] {
        task.runs.sorted { $0.startedAt > $1.startedAt }
    }

    private var upcomingRuns: [Date] {
        ScheduleCalculator.nextRuns(for: task.schedule, count: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: runs list
            VStack(spacing: 0) {
                HStack {
                    Text("Runs")
                        .font(.headline)
                    Spacer()
                    Button(action: { showRuns = false }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                List(selection: $selectedRun) {
                    if !upcomingRuns.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcomingRuns, id: \.self) { date in
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundStyle(.orange)
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
            .frame(height: listHeight)

            // Drag handle
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            listHeight = max(100, listHeight + value.translation.height)
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            Divider()

            // Bottom: log detail for selected run
            if let run = selectedRun {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if run.runStatus == .running {
                            Button(action: { cancelRun(run) }) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .help("Stop this run")
                        }
                        if run.sessionId != nil {
                            Menu {
                                Button("Open in Terminal") { openInTerminal(run: run, app: "Terminal") }
                                Button("Open in iTerm") { openInTerminal(run: run, app: "iTerm") }
                            } label: {
                                Text("Open Session")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Tab bar
                    Picker("View", selection: $selectedTab) {
                        ForEach(OutputTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Content
                    ScrollView {
                        Text(contentForTab(run))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    Divider()

                    // Status bar
                    HStack {
                        if let sid = run.sessionId {
                            Text("Session: \(sid)")
                                .font(.caption.monospaced())
                        }
                        Spacer()
                        Text(run.runStatus.rawValue)
                            .font(.caption)
                        if let code = run.exitCode {
                            Text("Code: \(code)")
                                .font(.caption.monospaced())
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Run", systemImage: "doc.text.magnifyingglass", description: Text("Select a run above to view its logs"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedRun == nil {
                selectedRun = sortedRuns.first
            }
        }
    }

    private func cancelRun(_ run: TaskRun) {
        LaunchdService.shared.cancelRun(run, modelContext: modelContext)
    }

    private func contentForTab(_ run: TaskRun) -> String {
        switch selectedTab {
        case .output: return run.formattedOutput.isEmpty ? "No output yet" : run.formattedOutput
        case .rawOutput: return run.rawOutput.isEmpty ? "No raw output" : run.rawOutput
        case .errors: return ""
        case .debug: return run.debugLog.isEmpty ? "No debug log" : run.debugLog
        }
    }

    static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func openInTerminal(run: TaskRun, app: String) {
        guard let dir = run.task?.directory else { return }
        let safeDir = Self.escapeForAppleScript(dir)
        let safeSid = Self.escapeForAppleScript(run.sessionId ?? "")
        let script: String
        if app == "iTerm" {
            script = """
            tell application "iTerm"
                create window with default profile command "cd \(safeDir) && claude --resume \(safeSid)"
            end tell
            """
        } else {
            script = "tell application \"Terminal\" to do script \"cd \(safeDir)\""
        }
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
