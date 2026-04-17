import XCTest
@testable import ccsplit_app

final class SessionStatusTests: XCTestCase {
    func testStartToRunning() {
        XCTAssertEqual(SessionStatus.transitioned(current: nil, event: .sessionStart), .running)
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
