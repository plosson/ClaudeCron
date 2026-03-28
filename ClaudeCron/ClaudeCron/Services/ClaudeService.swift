import Foundation

@Observable
@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private var runningProcesses: [UUID: Process] = [:]

    /// Cached login shell environment (resolved once)
    nonisolated static let shellEnvironment: [String: String] = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "env"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        var env: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eqIdx])
            let value = String(line[line.index(after: eqIdx)...])
            env[key] = value
        }
        // Ensure we at least have the current process env as fallback
        if env["PATH"] == nil {
            env = ProcessInfo.processInfo.environment
        }
        return env
    }()

    /// Find the claude CLI binary path (user override, then auto-detect)
    nonisolated func claudePath() -> String? {
        // Check for user override first
        let override = UserDefaults.standard.string(forKey: "claudeExecutablePath") ?? ""
        if !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        return autoDetectClaudePath()
    }

    /// Auto-detect claude binary using the cached shell PATH + common locations
    nonisolated func autoDetectClaudePath() -> String? {
        let shellPath = Self.shellEnvironment["PATH"] ?? ""
        let dirs = shellPath.components(separatedBy: ":")
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Fallback: check common install locations not always in PATH
        let home = NSHomeDirectory()
        let fallbacks = [
            "\(home)/.claude/local/bin/claude",
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in fallbacks {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Run a Claude task and stream output
    func runTask(
        prompt: String,
        directory: String,
        model: String,
        permissionMode: String,
        sessionMode: SessionMode,
        sessionId: String?,
        allowedTools: [String],
        disallowedTools: [String],
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onLog: @MainActor @escaping @Sendable (String) -> Void = { _ in },
        onComplete: @MainActor @escaping @Sendable (Int32, String?) -> Void
    ) -> UUID? {
        onLog("Resolving claude binary path...")
        guard let claudeBin = claudePath() else {
            onLog("ERROR: Could not find claude CLI binary")
            onLog("Checked: `which claude` via login shell")
            onLog("Checked: ~/.local/bin/claude, /usr/local/bin/claude, /opt/homebrew/bin/claude")
            onComplete(-1, nil)
            return nil
        }
        onLog("Found claude at: \(claudeBin)")

        let runId = UUID()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Run claude directly — no shell wrapping, avoids quoting issues
        process.executableURL = URL(fileURLWithPath: claudeBin)

        // Use the user's login shell environment
        var env = Self.shellEnvironment
        env.removeValue(forKey: "CLAUDECODE")
        process.environment = env

        let args = buildArgs(
            claudeBin: claudeBin,
            prompt: prompt,
            model: model,
            permissionMode: permissionMode,
            sessionMode: sessionMode,
            sessionId: sessionId,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools
        )

        // Skip the first element (claudeBin) since it's the executable
        process.arguments = Array(args.dropFirst())
        let expandedDirectory = NSString(string: directory).expandingTildeInPath
        process.currentDirectoryURL = URL(fileURLWithPath: expandedDirectory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        onLog("Working directory: \(directory)")
        onLog("Arguments: \(process.arguments!.joined(separator: " "))")

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in onOutput(str) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.runningProcesses.removeValue(forKey: runId)
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                let sid = self?.extractSessionId(from: errorStr)
                onLog("Process exited with code: \(proc.terminationStatus)")
                if !errorStr.isEmpty {
                    onLog("Stderr: \(errorStr)")
                }
                if let sid { onLog("Session ID: \(sid)") }
                onComplete(proc.terminationStatus, sid)
            }
        }

        do {
            try process.run()
            onLog("Process launched (PID: \(process.processIdentifier))")
            runningProcesses[runId] = process
            return runId
        } catch {
            onLog("ERROR: Failed to launch process: \(error.localizedDescription)")
            onComplete(-1, nil)
            return nil
        }
    }

    /// Generate a short description of what a prompt does, using Haiku
    nonisolated func summarizePrompt(_ prompt: String, completion: @escaping @Sendable (String?) -> Void) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let claudeBin = claudePath() else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: claudeBin)
            process.arguments = [
                "--print", "--model", "haiku", "--max-turns", "1",
                "Describe in one short sentence (max 15 words) what this Claude task prompt does. Output ONLY the description, no quotes or preamble:\n\n\(prompt)"
            ]
            var env = Self.shellEnvironment
            env.removeValue(forKey: "CLAUDECODE")
            process.environment = env
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(result.isEmpty ? nil : result)
            } catch {
                completion(nil)
            }
        }
    }

    func cancelRun(_ id: UUID) {
        runningProcesses[id]?.terminate()
        runningProcesses.removeValue(forKey: id)
    }

    /// Build the argument list for the claude CLI invocation
    func buildArgs(
        claudeBin: String,
        prompt: String,
        model: String,
        permissionMode: String,
        sessionMode: SessionMode,
        sessionId: String?,
        allowedTools: [String],
        disallowedTools: [String]
    ) -> [String] {
        var args = [claudeBin, "--print", "--output-format", "stream-json", "--verbose"]
        args += ["--model", model]

        switch permissionMode {
        case PermissionMode.bypass.rawValue:
            args += ["--dangerously-skip-permissions"]
        case PermissionMode.plan.rawValue:
            args += ["--permission-mode", "plan"]
        case PermissionMode.acceptEdits.rawValue:
            args += ["--permission-mode", "acceptEdits"]
        default:
            break // default mode — no flag needed
        }

        switch sessionMode {
        case .resume:
            if let sid = sessionId { args += ["--resume", sid] }
        case .fork:
            if let sid = sessionId { args += ["--resume", sid, "--fork-session"] }
        case .new:
            break
        }

        for tool in allowedTools where !tool.isEmpty {
            args += ["--allowedTools", tool]
        }
        for tool in disallowedTools where !tool.isEmpty {
            args += ["--disallowedTools", tool]
        }

        // Prompt is a positional argument (must come last)
        args += [prompt]
        return args
    }

    func extractSessionId(from output: String) -> String? {
        let pattern = /session_id["\s:]+([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})/
        if let match = output.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }
}
