import XCTest
@testable import ccfocus

final class PanelCloseDecisionTests: XCTestCase {
    func testAttentionClearedDuringPeekSuppressesClose() {
        let d = PanelCloseDecision.decide(reason: .attentionCleared, isPeekActive: true, isCcfocusFrontmost: true)
        XCTAssertFalse(d.shouldClose)
        XCTAssertFalse(d.shouldCommit)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testAttentionClearedNoPeekAndCcfocusFrontmostRestores() {
        let d = PanelCloseDecision.decide(reason: .attentionCleared, isPeekActive: false, isCcfocusFrontmost: true)
        XCTAssertTrue(d.shouldClose)
        XCTAssertFalse(d.shouldCommit)
        XCTAssertTrue(d.shouldRestoreFrontmost)
    }

    func testAttentionClearedNoPeekAndCcfocusNotFrontmostDoesNotRestore() {
        let d = PanelCloseDecision.decide(reason: .attentionCleared, isPeekActive: false, isCcfocusFrontmost: false)
        XCTAssertTrue(d.shouldClose)
        XCTAssertFalse(d.shouldCommit)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testUserEscapeWithPeekCommits() {
        let d = PanelCloseDecision.decide(reason: .userEscape, isPeekActive: true, isCcfocusFrontmost: true)
        XCTAssertTrue(d.shouldClose)
        XCTAssertTrue(d.shouldCommit)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testUserEscapeNoPeekAndCcfocusFrontmostRestores() {
        let d = PanelCloseDecision.decide(reason: .userEscape, isPeekActive: false, isCcfocusFrontmost: true)
        XCTAssertTrue(d.shouldClose)
        XCTAssertFalse(d.shouldCommit)
        XCTAssertTrue(d.shouldRestoreFrontmost)
    }

    func testUserHotkeyNoPeekAndCcfocusFrontmostRestores() {
        let d = PanelCloseDecision.decide(reason: .userHotkey, isPeekActive: false, isCcfocusFrontmost: true)
        XCTAssertTrue(d.shouldClose)
        XCTAssertTrue(d.shouldRestoreFrontmost)
    }

    func testCommittedViaRowNeverRestores() {
        let d = PanelCloseDecision.decide(reason: .committedViaRow, isPeekActive: false, isCcfocusFrontmost: true)
        XCTAssertTrue(d.shouldClose)
        XCTAssertFalse(d.shouldCommit)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testClickOutsideWithPeekCommits() {
        let d = PanelCloseDecision.decide(reason: .clickOutside, isPeekActive: true, isCcfocusFrontmost: false)
        XCTAssertTrue(d.shouldClose)
        XCTAssertTrue(d.shouldCommit)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testClickOutsideNoPeekNeverRestores() {
        let d = PanelCloseDecision.decide(reason: .clickOutside, isPeekActive: false, isCcfocusFrontmost: false)
        XCTAssertTrue(d.shouldClose)
        XCTAssertFalse(d.shouldRestoreFrontmost)
    }

    func testStatusButtonToggleBehavesLikeUserEscape() {
        XCTAssertEqual(
            PanelCloseDecision.decide(reason: .statusButtonToggle, isPeekActive: false, isCcfocusFrontmost: true).shouldRestoreFrontmost,
            PanelCloseDecision.decide(reason: .userEscape, isPeekActive: false, isCcfocusFrontmost: true).shouldRestoreFrontmost
        )
    }
}
