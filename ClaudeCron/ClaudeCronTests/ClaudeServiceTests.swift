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
