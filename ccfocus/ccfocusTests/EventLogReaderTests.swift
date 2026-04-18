import XCTest
@testable import ccfocus

final class EventLogReaderTests: XCTestCase {
    func testParsesSessionStart() throws {
        let line =
            #"{"ts":"2026-04-16T09:12:34.567Z","event":"session_start","session_id":"abc","#
            + #""terminal_id":"B9BE","cwd":"/tmp","git_branch":"main","claude_pid":123,"#
            + #""claude_start_time":"Wed Apr 16 09:12:34 2026","claude_comm":"claude"}"#
        let event = try EventLogReader.decode(line: line)
        switch event.kind {
        case .sessionStart(let start):
            XCTAssertEqual(start.sessionId, "abc")
            XCTAssertEqual(start.terminalId, "B9BE")
            XCTAssertEqual(start.gitBranch, "main")
            XCTAssertEqual(start.claudePid, 123)
        default:
            XCTFail("expected session_start")
        }
    }

    func testParsesStop() throws {
        let line = #"{"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"abc"}"#
        let event = try EventLogReader.decode(line: line)
        if case .stop(let sid, _) = event.kind {
            XCTAssertEqual(sid, "abc")
        } else {
            XCTFail("expected stop event")
        }
    }

    func testSkipsBlankLines() throws {
        let content = """
        {"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"a"}

        {"ts":"2026-04-16T09:15:01.000Z","event":"stop","session_id":"b"}
        """
        let events = try EventLogReader.decodeAll(content: content)
        XCTAssertEqual(events.count, 2)
    }

    func testIgnoresCorruptLine() throws {
        let content = """
        {"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"a"}
        this is not json
        {"ts":"2026-04-16T09:15:02.000Z","event":"stop","session_id":"b"}
        """
        let events = try EventLogReader.decodeAll(content: content)
        XCTAssertEqual(events.count, 2)
    }
}
