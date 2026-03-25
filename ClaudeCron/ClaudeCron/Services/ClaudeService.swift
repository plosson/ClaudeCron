import Foundation

@Observable
final class ClaudeService {
    static let shared = ClaudeService()

    private var runningProcesses: [UUID: Process] = [:]

    /// Find the claude CLI binary path
    func claudePath() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
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
        onOutput: @escaping (String) -> Void,
        onComplete: @escaping (Int32, String?) -> Void
    ) -> UUID? {
        guard let claudeBin = claudePath() else {
            onComplete(-1, nil)
            return nil
        }

        let runId = UUID()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        var args = [claudeBin, "--print", "--output-format", "json"]
        args += ["--model", model]

        if permissionMode == PermissionMode.bypass.rawValue {
            args += ["--dangerously-skip-permissions"]
        }

        switch sessionMode {
        case .resume:
            if let sid = sessionId { args += ["--resume", sid] }
        case .fork:
            if let sid = sessionId { args += ["--resume", sid] }
        case .new:
            break
        }

        for tool in allowedTools where !tool.isEmpty {
            args += ["--allowedTools", tool]
        }
        for tool in disallowedTools where !tool.isEmpty {
            args += ["--disallowedTools", tool]
        }

        args += ["--prompt", prompt]

        process.arguments = ["-l", "-c", args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onOutput(str) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.runningProcesses.removeValue(forKey: runId)
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                let sid = self?.extractSessionId(from: errorStr)
                onComplete(proc.terminationStatus, sid)
            }
        }

        do {
            try process.run()
            runningProcesses[runId] = process
            return runId
        } catch {
            onComplete(-1, nil)
            return nil
        }
    }

    func cancelRun(_ id: UUID) {
        runningProcesses[id]?.terminate()
        runningProcesses.removeValue(forKey: id)
    }

    func extractSessionId(from output: String) -> String? {
        let pattern = /session_id["\s:]+([a-f0-9-]+)/
        if let match = output.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }
}
