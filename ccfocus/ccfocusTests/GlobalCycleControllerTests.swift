import XCTest
@testable import ccfocus

@MainActor
final class GlobalCycleControllerTests: XCTestCase {
    private final class FakeFocuser: TerminalFocusing {
        var focused: [String] = []
        func focus(terminalId: String) { focused.append(terminalId) }
    }

    private func seed(_ state: AppState, entries: [(sid: String, tid: String?, status: SessionStatus, ts: String)]) {
        for (sid, tid, status, ts) in entries {
            state.registry.sessions[sid] = SessionEntry(
                sessionId: sid,
                terminalId: tid,
                cwd: "/tmp/\(sid)",
                gitBranch: nil,
                claudePid: nil,
                claudeStartTime: nil,
                claudeComm: nil,
                status: status,
                lastEventTs: ts,
                lastMessage: nil,
                deceasedReason: nil,
                startedAt: ts
            )
        }
    }

    func testFirstPressFromNilAnchorSelectsHead() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", .idle, "2026-04-27T00:00:03Z"),
            ("b", "t2", .idle, "2026-04-27T00:00:02Z"),
            ("c", "t3", .idle, "2026-04-27T00:00:01Z")
        ])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        let target = controller.cycleNext(state: state)
        XCTAssertEqual(target?.sessionId, "a")
        XCTAssertEqual(controller.anchorSessionId, "a")
        XCTAssertEqual(focuser.focused, ["t1"])
    }

    func testAdvancesAndWraps() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", .idle, "2026-04-27T00:00:03Z"),
            ("b", "t2", .idle, "2026-04-27T00:00:02Z"),
            ("c", "t3", .idle, "2026-04-27T00:00:01Z")
        ])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "a")
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "b")
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "c")
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "a")
        XCTAssertEqual(focuser.focused, ["t1", "t2", "t3", "t1"])
    }

    func testAnchorMissingFromCandidatesRestartsFromHead() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", .idle, "2026-04-27T00:00:03Z"),
            ("b", "t2", .idle, "2026-04-27T00:00:02Z")
        ])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        _ = controller.cycleNext(state: state) // anchor = a
        state.registry.sessions["a"]?.status = .deceased
        let target = controller.cycleNext(state: state)
        XCTAssertEqual(target?.sessionId, "b")
        XCTAssertEqual(controller.anchorSessionId, "b")
    }

    func testEmptyCandidatesReturnsNilAndResetsAnchor() {
        let state = AppState()
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        XCTAssertNil(controller.cycleNext(state: state))
        XCTAssertNil(controller.anchorSessionId)
        XCTAssertTrue(focuser.focused.isEmpty)
    }

    func testSkipsDeceasedAndUnlinkedSessions() {
        let state = AppState()
        seed(state, entries: [
            ("a", nil, .idle, "2026-04-27T00:00:03Z"),
            ("b", "t2", .deceased, "2026-04-27T00:00:02Z"),
            ("c", "t3", .idle, "2026-04-27T00:00:01Z")
        ])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        let target = controller.cycleNext(state: state)
        XCTAssertEqual(target?.sessionId, "c")
        XCTAssertEqual(focuser.focused, ["t3"])
    }

    func testSingleCandidateRecyclesItself() {
        let state = AppState()
        seed(state, entries: [
            ("a", "t1", .idle, "2026-04-27T00:00:01Z")
        ])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "a")
        XCTAssertEqual(controller.cycleNext(state: state)?.sessionId, "a")
        XCTAssertEqual(focuser.focused, ["t1", "t1"])
    }

    func testResetClearsAnchor() {
        let state = AppState()
        seed(state, entries: [("a", "t1", .idle, "2026-04-27T00:00:01Z")])
        let focuser = FakeFocuser()
        let controller = GlobalCycleController(focuser: focuser)
        _ = controller.cycleNext(state: state)
        controller.reset()
        XCTAssertNil(controller.anchorSessionId)
    }
}
