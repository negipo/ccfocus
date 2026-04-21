import XCTest
@testable import ccfocus

final class PopoverAutoCloseGateTests: XCTestCase {
    func testInitiallyDoesNotFire() {
        var gate = PopoverAutoCloseGate()
        XCTAssertFalse(gate.apply(current: 0))
    }

    func testFiresWhenDroppingFromPositiveToZero() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 2)
        XCTAssertTrue(gate.apply(current: 0))
    }

    func testDoesNotFireWhenStayingPositive() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 2)
        XCTAssertFalse(gate.apply(current: 1))
    }

    func testDoesNotFireWhenAlreadyZero() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 0)
        XCTAssertFalse(gate.apply(current: 0))
    }

    func testFiresOnEachDropAfterRebound() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 1)
        XCTAssertTrue(gate.apply(current: 0))
        _ = gate.apply(current: 1)
        XCTAssertTrue(gate.apply(current: 0))
    }

    func testSyncSetsBaselineSoUnchangedCountDoesNotFire() {
        var gate = PopoverAutoCloseGate()
        gate.sync(to: 3)
        XCTAssertFalse(gate.apply(current: 3))
    }

    func testSyncBaselineStillDetectsDropToZero() {
        var gate = PopoverAutoCloseGate()
        gate.sync(to: 3)
        XCTAssertTrue(gate.apply(current: 0))
    }
}
