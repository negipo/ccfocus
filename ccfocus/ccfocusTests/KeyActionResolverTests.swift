import XCTest
@testable import ccfocus

final class KeyActionResolverTests: XCTestCase {
    func testKey1MapsToIndex0() {
        XCTAssertEqual(KeyActionResolver.numberIndex(forCharacter: "1"), 0)
    }

    func testKey9MapsToIndex8() {
        XCTAssertEqual(KeyActionResolver.numberIndex(forCharacter: "9"), 8)
    }

    func testKey0MapsToIndex9() {
        XCTAssertEqual(KeyActionResolver.numberIndex(forCharacter: "0"), 9)
    }

    func testNonDigitReturnsNil() {
        XCTAssertNil(KeyActionResolver.numberIndex(forCharacter: "a"))
        XCTAssertNil(KeyActionResolver.numberIndex(forCharacter: " "))
    }

    func testSelectReturnsEntryWithinBounds() {
        let entries = Self.makeEntries(count: 5)
        let selected = KeyActionResolver.select(from: entries, numberIndex: 2)
        XCTAssertEqual(selected?.sessionId, "s2")
    }

    func testSelectReturnsNilWhenOutOfBounds() {
        let entries = Self.makeEntries(count: 3)
        XCTAssertNil(KeyActionResolver.select(from: entries, numberIndex: 5))
    }

    func testSelectReturnsNilWhenEmpty() {
        XCTAssertNil(KeyActionResolver.select(from: [], numberIndex: 0))
    }

    func testSelectRespectsTenItemLimit() {
        let entries = Self.makeEntries(count: 15)
        let selected = KeyActionResolver.select(from: entries, numberIndex: 9)
        XCTAssertEqual(selected?.sessionId, "s9")
        XCTAssertNil(KeyActionResolver.select(from: entries, numberIndex: 10))
    }

    private static func makeEntries(count: Int) -> [SessionEntry] {
        (0..<count).map { i in
            SessionEntry(
                sessionId: "s\(i)",
                terminalId: nil,
                cwd: "/tmp/\(i)",
                gitBranch: nil,
                claudePid: nil,
                claudeStartTime: nil,
                claudeComm: nil,
                status: .running,
                lastEventTs: "",
                lastMessage: nil,
                deceasedReason: nil,
                startedAt: ""
            )
        }
    }
}
