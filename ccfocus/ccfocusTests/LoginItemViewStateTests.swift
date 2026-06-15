import ServiceManagement
import XCTest
@testable import ccfocus

final class LoginItemViewStateTests: XCTestCase {
    func testEnabledStatusTurnsToggleOnWithoutApproval() {
        let state = LoginItemViewState(status: .enabled)
        XCTAssertTrue(state.isEnabled)
        XCTAssertFalse(state.needsApproval)
        XCTAssertNil(state.approvalText)
    }

    func testNotRegisteredStatusTurnsToggleOff() {
        let state = LoginItemViewState(status: .notRegistered)
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.needsApproval)
        XCTAssertNil(state.approvalText)
    }

    func testNotFoundStatusTurnsToggleOff() {
        let state = LoginItemViewState(status: .notFound)
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.needsApproval)
    }

    func testRequiresApprovalKeepsToggleOnAndShowsApprovalText() {
        let state = LoginItemViewState(status: .requiresApproval)
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.needsApproval)
        XCTAssertNotNil(state.approvalText)
    }
}
