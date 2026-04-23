import XCTest
@testable import ccfocus

final class BranchTextTruncatorTests: XCTestCase {
    func testShortStringIsUnchanged() {
        XCTAssertEqual(BranchTextTruncator.truncate("main"), "main")
    }

    func testExactlyAtLimitIsUnchanged() {
        let s = String(repeating: "a", count: BranchTextTruncator.defaultTotal)
        XCTAssertEqual(BranchTextTruncator.truncate(s), s)
    }

    func testLongStringCollapsesToDefaultTotal() {
        let input = "po/issue-23-refire-and-return-close"
        let out = BranchTextTruncator.truncate(input)
        XCTAssertEqual(out.count, BranchTextTruncator.defaultTotal)
        XCTAssertTrue(out.contains(".."))
        XCTAssertTrue(out.hasPrefix("po/issue-"))
        XCTAssertTrue(out.hasSuffix("urn-close"))
    }

    func testOddKeepSplitsHeadLarger() {
        let input = "abcdefghijklmnopqrstuvwxyz"
        let out = BranchTextTruncator.truncate(input, total: 11)
        XCTAssertEqual(out.count, 11)
        XCTAssertEqual(out, "abcde..wxyz")
    }

    func testTotalSmallerThanEllipsisReturnsOriginal() {
        XCTAssertEqual(BranchTextTruncator.truncate("abcdef", total: 1), "abcdef")
    }
}
