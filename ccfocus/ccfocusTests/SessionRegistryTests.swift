import XCTest
@testable import ccfocus

final class SessionRegistryTests: XCTestCase {
    private func parse(_ lines: [String]) throws -> [Event] {
        try lines.map { try EventLogReader.decode(line: $0) }
    }

    func testRegistersOneSessionOnStart() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":1,"claude_start_time":"x","claude_comm":"claude"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions.count, 1)
        let s = reg.sessions["s1"]!
        XCTAssertEqual(s.terminalId, "T1")
        XCTAssertEqual(s.gitBranch, "main")
        XCTAssertEqual(s.status, .idle)
    }

    func testNotificationMovesToWaitingInput() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"notification","session_id":"s1","message":"Approve bash"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .waitingInput)
        XCTAssertEqual(reg.sessions["s1"]?.lastMessage, "Approve bash")
    }

    func testNewSessionStartRetiresSamePidSession() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":100,"claude_start_time":"Thu Apr 16 20:22:22 2026","claude_comm":"claude"}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"notification","session_id":"s1","message":"waiting"}"#,
            #"{"ts":"2026-04-16T09:05:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":100,"claude_start_time":"Thu Apr 16 20:22:22 2026","claude_comm":"claude"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .deceased)
        XCTAssertEqual(reg.sessions["s2"]?.status, .idle)
    }

    func testIdleSessionBecomesStaleAfter30Min() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .idle)

        let now = ISO8601DateFormatter().date(from: "2026-04-16T09:31:00Z")!
        reg.applyStaleAfter(now)
        XCTAssertEqual(reg.sessions["s1"]?.status, .stale)
    }

    func testSortedByLastEventDesc() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T2","cwd":"/b","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:05:00.000Z","event":"user_prompt_submit","session_id":"s1"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        let sorted = reg.sortedByLastEventDesc()
        XCTAssertEqual(sorted.map(\.sessionId), ["s1", "s2"])
    }

    func testStopWithHasQuestionSetsAsking() throws {
        var reg = SessionRegistry()
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","session_id":"s","cwd":"/tmp"}"#))
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:01.000Z","event":"stop","session_id":"s","has_question":true}"#))
        XCTAssertEqual(reg.sessions["s"]?.status, .asking)
    }

    func testStopWithoutHasQuestionSetsDone() throws {
        var reg = SessionRegistry()
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","session_id":"s","cwd":"/tmp"}"#))
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:01.000Z","event":"stop","session_id":"s"}"#))
        XCTAssertEqual(reg.sessions["s"]?.status, .done)
    }

    func testAskingBecomesStaleAfter30Min() throws {
        var reg = SessionRegistry()
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","session_id":"s","cwd":"/tmp"}"#))
        reg.apply(try EventLogReader.decode(line: #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"s","has_question":true}"#))
        let now = ISO8601DateFormatter().date(from: "2026-04-18T00:30:30Z")!
        reg.applyStaleAfter(now)
        XCTAssertEqual(reg.sessions["s"]?.status, .stale)
    }
}
