import XCTest
@testable import ccfocus_app

final class ManualPairingsStoreTests: XCTestCase {
    func testSaveAndLoadRoundtrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var store = ManualPairingsStore(fileURL: tmp)
        store.set(sessionId: "s1", terminalId: "T1")
        store.set(sessionId: "s2", terminalId: "T2")
        try store.save()

        var loaded = ManualPairingsStore(fileURL: tmp)
        try loaded.load()
        XCTAssertEqual(loaded.get(sessionId: "s1"), "T1")
        XCTAssertEqual(loaded.get(sessionId: "s2"), "T2")
    }

    func testLoadMissingFileReturnsEmpty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var s = ManualPairingsStore(fileURL: tmp)
        try s.load()
        XCTAssertNil(s.get(sessionId: "x"))
    }

    func testRemoveTerminalCascadesDeletion() {
        var s = ManualPairingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        s.set(sessionId: "s1", terminalId: "T1")
        s.set(sessionId: "s2", terminalId: "T1")
        s.set(sessionId: "s3", terminalId: "T2")
        s.removePairingsReferring(terminalIds: ["T1"])
        XCTAssertNil(s.get(sessionId: "s1"))
        XCTAssertNil(s.get(sessionId: "s2"))
        XCTAssertEqual(s.get(sessionId: "s3"), "T2")
    }
}
