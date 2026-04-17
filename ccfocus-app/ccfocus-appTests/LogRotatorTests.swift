import XCTest
@testable import ccfocus_app

final class LogRotatorTests: XCTestCase {
    func testDeletesFilesOlderThan7Days() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let today = Date()
        let old = Calendar.current.date(byAdding: .day, value: -10, to: today)!
        let recent = Calendar.current.date(byAdding: .day, value: -3, to: today)!

        let oldURL = tmp.appendingPathComponent(LogRotator.nameFor(date: old))
        let recentURL = tmp.appendingPathComponent(LogRotator.nameFor(date: recent))
        FileManager.default.createFile(atPath: oldURL.path, contents: Data("".utf8))
        FileManager.default.createFile(atPath: recentURL.path, contents: Data("".utf8))

        LogRotator.rotate(directory: tmp, now: today, retentionDays: 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }
}
