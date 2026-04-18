import XCTest
@testable import ccfocus

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
        var store = ManualPairingsStore(fileURL: tmp)
        try store.load()
        XCTAssertNil(store.get(sessionId: "x"))
    }

    func testRemoveTerminalCascadesDeletion() {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var store = ManualPairingsStore(fileURL: tmpURL)
        store.set(sessionId: "s1", terminalId: "T1")
        store.set(sessionId: "s2", terminalId: "T1")
        store.set(sessionId: "s3", terminalId: "T2")
        store.removePairingsReferring(terminalIds: ["T1"])
        XCTAssertNil(store.get(sessionId: "s1"))
        XCTAssertNil(store.get(sessionId: "s2"))
        XCTAssertEqual(store.get(sessionId: "s3"), "T2")
    }
}
