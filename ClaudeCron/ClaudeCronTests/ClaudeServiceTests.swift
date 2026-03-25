import XCTest
@testable import ClaudeCron

final class ClaudeServiceTests: XCTestCase {

    func testExtractSessionIdFromValidOutput() {
        let service = ClaudeService.shared
        let output = """
        session_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        """
        let sid = service.extractSessionId(from: output)
        XCTAssertEqual(sid, "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
    }

    func testExtractSessionIdWithNoMatch() {
        let service = ClaudeService.shared
        let sid = service.extractSessionId(from: "no session here")
        XCTAssertNil(sid)
    }

    func testExtractSessionIdFromEmptyString() {
        let service = ClaudeService.shared
        let sid = service.extractSessionId(from: "")
        XCTAssertNil(sid)
    }

    // MARK: - buildArgs

    private let bin = "/usr/local/bin/claude"

    func testBuildArgsBasic() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "hello", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: [], disallowedTools: []
        )
        XCTAssertEqual(args[0], bin)
        XCTAssertTrue(args.contains("--print"))
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("sonnet"))
        // Prompt is positional (last), NOT preceded by --prompt
        XCTAssertEqual(args.last, "hello")
        XCTAssertFalse(args.contains("--prompt"), "--prompt is not a valid claude CLI flag")
    }

    func testBuildArgsBypassPermissions() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "opus",
            permissionMode: "bypassPermissions", sessionMode: .new,
            sessionId: nil, allowedTools: [], disallowedTools: []
        )
        XCTAssertTrue(args.contains("--dangerously-skip-permissions"))
    }

    func testBuildArgsDefaultPermissionsNoDangerousFlag() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: [], disallowedTools: []
        )
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
    }

    func testBuildArgsResumeSession() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .resume,
            sessionId: "abc-123", allowedTools: [], disallowedTools: []
        )
        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("abc-123"))
        XCTAssertFalse(args.contains("--fork-session"))
    }

    func testBuildArgsResumeWithoutSessionIdNoResumeFlag() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .resume,
            sessionId: nil, allowedTools: [], disallowedTools: []
        )
        XCTAssertFalse(args.contains("--resume"))
    }

    func testBuildArgsForkSession() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .fork,
            sessionId: "abc-123", allowedTools: [], disallowedTools: []
        )
        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("abc-123"))
        XCTAssertTrue(args.contains("--fork-session"))
    }

    func testBuildArgsAllowedTools() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: ["Read", "Write"], disallowedTools: []
        )
        let allowedIndices = args.enumerated().filter { $0.element == "--allowedTools" }.map { $0.offset }
        XCTAssertEqual(allowedIndices.count, 2)
        XCTAssertEqual(args[allowedIndices[0] + 1], "Read")
        XCTAssertEqual(args[allowedIndices[1] + 1], "Write")
    }

    func testBuildArgsDisallowedTools() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: [], disallowedTools: ["Bash"]
        )
        XCTAssertTrue(args.contains("--disallowedTools"))
        XCTAssertTrue(args.contains("Bash"))
    }

    func testBuildArgsEmptyToolsAreSkipped() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "test", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: ["", "Read", ""], disallowedTools: [""]
        )
        let allowedCount = args.filter { $0 == "--allowedTools" }.count
        XCTAssertEqual(allowedCount, 1, "Empty tool names should be skipped")
        XCTAssertFalse(args.contains("--disallowedTools"), "All-empty disallowed should produce no flag")
    }

    func testBuildArgsPromptIsAlwaysLast() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "my prompt here", model: "opus",
            permissionMode: "bypassPermissions", sessionMode: .resume,
            sessionId: "sid-1", allowedTools: ["Read"], disallowedTools: ["Bash"]
        )
        XCTAssertEqual(args.last, "my prompt here", "Prompt must be the last argument")
    }

    func testBuildArgsPromptWithSpaces() {
        let args = ClaudeService.shared.buildArgs(
            claudeBin: bin, prompt: "tell me the time", model: "sonnet",
            permissionMode: "default", sessionMode: .new,
            sessionId: nil, allowedTools: [], disallowedTools: []
        )
        XCTAssertEqual(args.last, "tell me the time")
    }

    // MARK: - extractSessionId

    func testExtractSessionIdVariousFormats() {
        let service = ClaudeService.shared

        // With quotes and colon
        let output1 = #"session_id":"abcd1234-5678-9abc-def0-123456789abc""#
        XCTAssertEqual(service.extractSessionId(from: output1),
                      "abcd1234-5678-9abc-def0-123456789abc")

        // With spaces
        let output2 = "session_id  abcd1234-5678-9abc-def0-123456789abc"
        XCTAssertEqual(service.extractSessionId(from: output2),
                      "abcd1234-5678-9abc-def0-123456789abc")
    }
}
