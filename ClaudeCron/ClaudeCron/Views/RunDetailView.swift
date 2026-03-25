import SwiftUI

enum OutputTab: String, CaseIterable {
    case output = "Output"
    case rawOutput = "Raw Output"
    case errors = "Errors"
    case debug = "Debug"
}

struct RunDetailView: View {
    let run: TaskRun
    @State private var selectedTab: OutputTab = .output

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                if run.sessionId != nil {
                    Menu {
                        Button("Open in Terminal") { openInTerminal(app: "Terminal") }
                        Button("Open in iTerm") { openInTerminal(app: "iTerm") }
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

            // Run title
            if let taskName = run.task?.name {
                Text("\(taskName) - \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

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
                Text(contentForTab)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            // Status bar
            HStack {
                if let sid = run.sessionId {
                    Text("Session ID: \(sid)")
                        .font(.caption.monospaced())
                }
                Spacer()
                Text("Status: \(run.runStatus.rawValue)")
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
    }

    private var contentForTab: String {
        switch selectedTab {
        case .output: return run.formattedOutput.isEmpty ? "No output yet" : run.formattedOutput
        case .rawOutput: return run.rawOutput.isEmpty ? "No raw output" : run.rawOutput
        case .errors: return "" // TODO: separate error stream
        case .debug: return run.debugLog.isEmpty ? "No debug log" : run.debugLog
        }
    }

    /// Escape a string for use inside an AppleScript double-quoted string.
    static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func openInTerminal(app: String) {
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
