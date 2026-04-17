import XCTest
@testable import ccfocus_app

final class EventLogReaderTests: XCTestCase {
    func testParsesSessionStart() throws {
        let line = #"{"ts":"2026-04-16T09:12:34.567Z","event":"session_start","session_id":"abc","terminal_id":"B9BE","cwd":"/tmp","git_branch":"main","claude_pid":123,"claude_start_time":"Wed Apr 16 09:12:34 2026","claude_comm":"claude"}"#
        let ev = try EventLogReader.decode(line: line)
        switch ev.kind {
        case .sessionStart(let s):
            XCTAssertEqual(s.sessionId, "abc")
            XCTAssertEqual(s.terminalId, "B9BE")
            XCTAssertEqual(s.gitBranch, "main")
            XCTAssertEqual(s.claudePid, 123)
        default:
            XCTFail("expected session_start")
        }
    }

    func testParsesStop() throws {
        let line = #"{"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"abc"}"#
        let ev = try EventLogReader.decode(line: line)
        if case .stop(let s) = ev.kind { XCTAssertEqual(s, "abc") } else { XCTFail() }
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
