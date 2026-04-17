import XCTest
@testable import ccsplit_app

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
        XCTAssertEqual(s.status, .running)
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
        XCTAssertEqual(reg.sessions["s2"]?.status, .running)
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
}
