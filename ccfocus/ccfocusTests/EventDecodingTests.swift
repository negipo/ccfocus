import XCTest
@testable import ccfocus

final class EventDecodingTests: XCTestCase {
    func testStopWithHasQuestionTrue() throws {
        let raw = #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"abc","has_question":true}"#
        let event = try EventLogReader.decode(line: raw)
        if case .stop(let sid, let hasQuestion) = event.kind {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(hasQuestion, true)
        } else {
            XCTFail("expected stop variant")
        }
    }

    func testStopWithoutHasQuestion() throws {
        let raw = #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"abc"}"#
        let event = try EventLogReader.decode(line: raw)
        if case .stop(_, let hasQuestion) = event.kind {
            XCTAssertNil(hasQuestion)
        } else {
            XCTFail("expected stop variant")
        }
    }
}
