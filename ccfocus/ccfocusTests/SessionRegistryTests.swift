import XCTest
@testable import ccfocus

final class SessionRegistryTests: XCTestCase {
    private func parse(_ lines: [String]) throws -> [Event] {
        try lines.map { try EventLogReader.decode(line: $0) }
    }

    func testRegistersOneSessionOnStart() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":1,"# +
            #""claude_start_time":"x","claude_comm":"claude"}"#
        ])
        var reg = SessionRegistry()
        for event in events { reg.apply(event) }
        XCTAssertEqual(reg.sessions.count, 1)
        let session = reg.sessions["s1"]!
        XCTAssertEqual(session.terminalId, "T1")
        XCTAssertEqual(session.gitBranch, "main")
        XCTAssertEqual(session.status, .idle)
    }

    func testNotificationMovesToWaitingInput() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"# +
            #""claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"notification","session_id":"s1","# +
            #""message":"Approve bash"}"#
        ])
        var reg = SessionRegistry()
        for event in events { reg.apply(event) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .waitingInput)
        XCTAssertEqual(reg.sessions["s1"]?.lastMessage, "Approve bash")
    }

    func testNewSessionStartRetiresSamePidSession() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":100,"# +
            #""claude_start_time":"Thu Apr 16 20:22:22 2026","claude_comm":"claude"}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"notification","session_id":"s1","# +
            #""message":"waiting"}"#,
            #"{"ts":"2026-04-16T09:05:00.000Z","event":"session_start","session_id":"s2","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":100,"# +
            #""claude_start_time":"Thu Apr 16 20:22:22 2026","claude_comm":"claude"}"#
        ])
        var reg = SessionRegistry()
        for event in events { reg.apply(event) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .deceased)
        XCTAssertEqual(reg.sessions["s2"]?.status, .idle)
    }

    func testIdleSessionBecomesStaleAfter30Min() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"# +
            #""claude_start_time":null,"claude_comm":null}"#
        ])
        var reg = SessionRegistry()
        for event in events { reg.apply(event) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .idle)

        let now = ISO8601DateFormatter().date(from: "2026-04-16T09:31:00Z")!
        reg.applyStaleAfter(now)
        XCTAssertEqual(reg.sessions["s1"]?.status, .stale)
    }

    func testSortedByLastEventDesc() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","# +
            #""terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"# +
            #""claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"session_start","session_id":"s2","# +
            #""terminal_id":"T2","cwd":"/b","git_branch":null,"claude_pid":null,"# +
            #""claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:05:00.000Z","event":"user_prompt_submit","session_id":"s1"}"#
        ])
        var reg = SessionRegistry()
        for event in events { reg.apply(event) }
        let sorted = reg.sortedByLastEventDesc()
        XCTAssertEqual(sorted.map(\.sessionId), ["s1", "s2"])
    }

    func testStopWithHasQuestionSetsAsking() throws {
        var reg = SessionRegistry()
        let startLine =
            #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","#
            + #""session_id":"s","cwd":"/tmp"}"#
        let stopLine =
            #"{"ts":"2026-04-18T00:00:01.000Z","event":"stop","#
            + #""session_id":"s","has_question":true}"#
        reg.apply(try EventLogReader.decode(line: startLine))
        reg.apply(try EventLogReader.decode(line: stopLine))
        XCTAssertEqual(reg.sessions["s"]?.status, .asking)
    }

    func testStopWithoutHasQuestionSetsDone() throws {
        var reg = SessionRegistry()
        let startLine =
            #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","#
            + #""session_id":"s","cwd":"/tmp"}"#
        let stopLine =
            #"{"ts":"2026-04-18T00:00:01.000Z","event":"stop","session_id":"s"}"#
        reg.apply(try EventLogReader.decode(line: startLine))
        reg.apply(try EventLogReader.decode(line: stopLine))
        XCTAssertEqual(reg.sessions["s"]?.status, .done)
    }

    func testAskingBecomesStaleAfter30Min() throws {
        var reg = SessionRegistry()
        let startLine =
            #"{"ts":"2026-04-18T00:00:00.000Z","event":"session_start","#
            + #""session_id":"s","cwd":"/tmp"}"#
        let stopLine =
            #"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","#
            + #""session_id":"s","has_question":true}"#
        reg.apply(try EventLogReader.decode(line: startLine))
        reg.apply(try EventLogReader.decode(line: stopLine))
        let now = ISO8601DateFormatter().date(from: "2026-04-18T00:30:30Z")!
        reg.applyStaleAfter(now)
        XCTAssertEqual(reg.sessions["s"]?.status, .stale)
    }

    func testAttentionCountIsZeroForEmptyRegistry() {
        let reg = SessionRegistry()
        XCTAssertEqual(reg.attentionCount, 0)
    }

    func testAttentionCountCountsAttentionStatuses() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"asking","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"asking","has_question":true}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"waiting","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"notification","session_id":"waiting","message":"m"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"done","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"done"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"idle","cwd":"/a"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        XCTAssertEqual(reg.sessions["asking"]?.status, .asking)
        XCTAssertEqual(reg.sessions["waiting"]?.status, .waitingInput)
        XCTAssertEqual(reg.sessions["done"]?.status, .done)
        XCTAssertEqual(reg.sessions["idle"]?.status, .idle)
        XCTAssertEqual(reg.attentionCount, 4)
    }

    func testAttentionCountExcludesNonAttentionStatuses() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"run","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"user_prompt_submit","session_id":"run"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"stale","cwd":"/a"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        let now = ISO8601DateFormatter().date(from: "2026-04-20T00:31:00Z")!
        reg.applyStaleAfter(now)
        reg.markDeceased(sid: "run", reason: .claudeTerminated)
        XCTAssertEqual(reg.sessions["run"]?.status, .deceased)
        XCTAssertEqual(reg.sessions["stale"]?.status, .stale)
        XCTAssertEqual(reg.attentionCount, 0)
    }

    func testAttentionCountMixedCount() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"a","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"a","has_question":true}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"b","cwd":"/b"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"user_prompt_submit","session_id":"b"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        XCTAssertEqual(reg.attentionCount, 1)
    }
}
