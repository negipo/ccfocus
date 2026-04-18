import XCTest
@testable import ccfocus

final class EventDecodingTests: XCTestCase {
    func testStopWithHasQuestionTrue() throws {
        let raw = #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"abc","has_question":true}"#
        let ev = try EventLogReader.decode(line: raw)
        if case .stop(let sid, let hq) = ev.kind {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(hq, true)
        } else {
            XCTFail("expected stop variant")
        }
    }

    func testStopWithoutHasQuestion() throws {
        let raw = #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"abc"}"#
        let ev = try EventLogReader.decode(line: raw)
        if case .stop(_, let hq) = ev.kind {
            XCTAssertNil(hq)
        } else {
            XCTFail("expected stop variant")
        }
    }
}
