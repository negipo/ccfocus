import XCTest
@testable import ccfocus

@MainActor
final class AppStateCycleTests: XCTestCase {
    private func seed(_ state: AppState, entries: [(sid: String, tid: String?, ts: String)]) {
        for (sid, tid, ts) in entries {
            state.registry.sessions[sid] = SessionEntry(
                sessionId: sid,
                terminalId: tid,
                cwd: "/tmp",
                gitBranch: nil,
                claudePid: nil,
                claudeStartTime: nil,
                claudeComm: nil,
                status: .idle,
                lastEventTs: ts,
                lastMessage: nil,
                deceasedReason: nil,
                startedAt: ts
            )
        }
    }

    func testForwardFromEmptyStateStartsAtFirst() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", "2026-04-22T00:00:03Z"),
            ("b", "t2", "2026-04-22T00:00:02Z"),
            ("c", "t3", "2026-04-22T00:00:01Z")
        ])
        let target = state.cycleSessionsOneStep(forward: true)
        XCTAssertEqual(target?.sessionId, "a")
        XCTAssertEqual(target?.terminalId, "t1")
        XCTAssertEqual(state.lastPeekedSessionId, "a")
        XCTAssertEqual(state.lastPeekedTerminalId, "t1")
    }

    func testForwardAdvancesThenWraps() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", "2026-04-22T00:00:03Z"),
            ("b", "t2", "2026-04-22T00:00:02Z"),
            ("c", "t3", "2026-04-22T00:00:01Z")
        ])
        _ = state.cycleSessionsOneStep(forward: true)
        XCTAssertEqual(state.cycleSessionsOneStep(forward: true)?.sessionId, "b")
        XCTAssertEqual(state.cycleSessionsOneStep(forward: true)?.sessionId, "c")
        XCTAssertEqual(state.cycleSessionsOneStep(forward: true)?.sessionId, "a")
    }

    func testBackwardFromEmptyStartsAtLast() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", "2026-04-22T00:00:03Z"),
            ("b", "t2", "2026-04-22T00:00:02Z"),
            ("c", "t3", "2026-04-22T00:00:01Z")
        ])
        let target = state.cycleSessionsOneStep(forward: false)
        XCTAssertEqual(target?.sessionId, "c")
    }

    func testSkipsUnlinkedSessions() {
        let state = AppState()
        seed(state, entries: [
            ("a", nil, "2026-04-22T00:00:03Z"),
            ("b", "t2", "2026-04-22T00:00:02Z")
        ])
        XCTAssertEqual(state.cycleSessionsOneStep(forward: true)?.sessionId, "b")
    }

    func testAllUnlinkedReturnsNil() {
        let state = AppState()
        seed(state, entries: [("a", nil, "2026-04-22T00:00:03Z")])
        XCTAssertNil(state.cycleSessionsOneStep(forward: true))
    }

    func testResolvesNextFromSnapshotEvenIfOrderChanges() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", "2026-04-22T00:00:03Z"),
            ("b", "t2", "2026-04-22T00:00:02Z"),
            ("c", "t3", "2026-04-22T00:00:01Z")
        ])
        _ = state.cycleSessionsOneStep(forward: true) // a
        _ = state.cycleSessionsOneStep(forward: true) // b
        state.registry.sessions["b"]?.lastEventTs = "2026-04-22T00:00:99Z"
        XCTAssertEqual(state.cycleSessionsOneStep(forward: true)?.sessionId, "a")
    }

    func testResetCycleStateClearsFields() {
        let state = AppState()
        seed(state, entries: [("a", "t1", "2026-04-22T00:00:01Z")])
        _ = state.cycleSessionsOneStep(forward: true)
        state.resetCycleState()
        XCTAssertNil(state.lastPeekedSessionId)
        XCTAssertNil(state.lastPeekedTerminalId)
    }

    func testCommitLastPeekClearsMessageAndDoneNotified() {
        let state = AppState()
        seed(state, entries: [("a", "t1", "2026-04-22T00:00:01Z")])
        state.registry.sessions["a"]?.lastMessage = "pending"
        state.registry.sessions["a"]?.doneNotified = true
        _ = state.cycleSessionsOneStep(forward: true)
        state.commitLastPeek()
        XCTAssertNil(state.registry.sessions["a"]?.lastMessage)
        XCTAssertEqual(state.registry.sessions["a"]?.doneNotified, false)
    }

    func testCommitLastPeekWithoutPeekDoesNothing() {
        let state = AppState()
        seed(state, entries: [("a", "t1", "2026-04-22T00:00:01Z")])
        state.registry.sessions["a"]?.lastMessage = "pending"
        state.registry.sessions["a"]?.doneNotified = true
        state.commitLastPeek()
        XCTAssertEqual(state.registry.sessions["a"]?.lastMessage, "pending")
        XCTAssertEqual(state.registry.sessions["a"]?.doneNotified, true)
    }
}
