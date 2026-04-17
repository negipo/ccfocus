import XCTest
@testable import ccfocus_app

final class PopoverStateTests: XCTestCase {
    func testInitialStateIsClosed() {
        let machine = PopoverStateMachine()
        XCTAssertEqual(machine.state, .closed)
    }

    func testHotkeyFromClosedRequestsOpenAndFocus() {
        var machine = PopoverStateMachine()
        let action = machine.handleHotkey()
        XCTAssertEqual(action, .showAndFocus)
    }

    func testHotkeyFromOpenUnfocusedRequestsFocus() {
        var machine = PopoverStateMachine()
        machine.markOpenedUnfocused()
        let action = machine.handleHotkey()
        XCTAssertEqual(action, .focus)
    }

    func testHotkeyFromOpenFocusedRequestsClose() {
        var machine = PopoverStateMachine()
        machine.markOpenedUnfocused()
        machine.markBecameKey()
        let action = machine.handleHotkey()
        XCTAssertEqual(action, .close)
    }

    func testBecameKeyTransitionsToFocused() {
        var machine = PopoverStateMachine()
        machine.markOpenedUnfocused()
        machine.markBecameKey()
        XCTAssertEqual(machine.state, .openFocused)
    }

    func testResignKeyDemotesFocusedToUnfocused() {
        var machine = PopoverStateMachine()
        machine.markOpenedUnfocused()
        machine.markBecameKey()
        machine.markResignedKey()
        XCTAssertEqual(machine.state, .openUnfocused)
    }

    func testResignKeyOnClosedIsNoop() {
        var machine = PopoverStateMachine()
        machine.markResignedKey()
        XCTAssertEqual(machine.state, .closed)
    }

    func testDidCloseTransitionsToClosed() {
        var machine = PopoverStateMachine()
        machine.markOpenedUnfocused()
        machine.markDidClose()
        XCTAssertEqual(machine.state, .closed)
    }
}
