import XCTest
@testable import ccfocus

final class LivenessCheckerTests: XCTestCase {
    func testAllMatch() {
        let info = PsInfo(pid: 123, lstart: "Wed Apr 16 09:12:34 2026", comm: "claude")
        let ok = LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info)
        XCTAssertTrue(ok)
    }
    func testStartTimeMismatchFails() {
        let info = PsInfo(pid: 123, lstart: "Thu Apr 17 10:00:00 2026", comm: "claude")
        XCTAssertFalse(LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info))
    }
    func testCommMismatchFails() {
        let info = PsInfo(pid: 123, lstart: "Wed Apr 16 09:12:34 2026", comm: "zsh")
        XCTAssertFalse(LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info))
    }
}
