import XCTest
@testable import ccfocus

final class SessionStatusTests: XCTestCase {
    func testStartToIdle() {
        XCTAssertEqual(SessionStatus.transitioned(current: nil, event: .sessionStart), .idle)
    }

    func testIdleToRunningOnUserPromptSubmit() {
        XCTAssertEqual(SessionStatus.transitioned(current: .idle, event: .userPromptSubmit), .running)
    }

    func testIdleToRunningOnPreToolUse() {
        XCTAssertEqual(SessionStatus.transitioned(current: .idle, event: .preToolUse), .running)
    }

    func testIdleToWaitingInputOnNotification() {
        XCTAssertEqual(SessionStatus.transitioned(current: .idle, event: .notification), .waitingInput)
    }

    func testIdleToDoneOnStop() {
        XCTAssertEqual(SessionStatus.transitioned(current: .idle, event: .stop), .done)
    }

    func testNotificationSetsWaitingInput() {
        XCTAssertEqual(SessionStatus.transitioned(current: .running, event: .notification), .waitingInput)
    }

    func testPreToolUseMovesWaitingToRunning() {
        XCTAssertEqual(SessionStatus.transitioned(current: .waitingInput, event: .preToolUse), .running)
    }

    func testStopMovesRunningToDone() {
        XCTAssertEqual(SessionStatus.transitioned(current: .running, event: .stop), .done)
    }

    func testUserPromptSubmitResurrectsDone() {
        XCTAssertEqual(SessionStatus.transitioned(current: .done, event: .userPromptSubmit), .running)
    }

    func testStaleResurrectsOnAnyEvent() {
        XCTAssertEqual(SessionStatus.transitioned(current: .stale, event: .notification), .waitingInput)
        XCTAssertEqual(SessionStatus.transitioned(current: .stale, event: .userPromptSubmit), .running)
    }

    func testDeceasedStays() {
        XCTAssertEqual(SessionStatus.transitioned(current: .deceased, event: .notification), .deceased)
    }
}
