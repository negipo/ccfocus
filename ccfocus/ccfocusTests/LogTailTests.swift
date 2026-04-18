import XCTest
@testable import ccfocus

final class LogTailTests: XCTestCase {
    func testReadNewReturnsAllLinesFirstTime() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("2026-04-16.jsonl")
        try "line1\nline2\n".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        let lines = reader.readNew(url: f)
        XCTAssertEqual(lines, ["line1", "line2"])
    }

    func testReadNewReturnsOnlyAppendedLines() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("d.jsonl")
        try "line1\n".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        _ = reader.readNew(url: f)
        let handle = try FileHandle(forWritingTo: f)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("line2\nline3\n".utf8))
        try handle.close()
        let lines = reader.readNew(url: f)
        XCTAssertEqual(lines, ["line2", "line3"])
    }

    func testReadNewHandlesPartialLineByReadingAgainNextTime() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("d.jsonl")
        try "lineA\npart".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        let first = reader.readNew(url: f)
        XCTAssertEqual(first, ["lineA"])
        let handle = try FileHandle(forWritingTo: f)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("ial\n".utf8))
        try handle.close()
        let second = reader.readNew(url: f)
        XCTAssertEqual(second, ["partial"])
    }
}
