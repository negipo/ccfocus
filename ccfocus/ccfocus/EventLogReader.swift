import Foundation

enum EventLogReader {
    static func decode(line: String) throws -> Event {
        let data = Data(line.utf8)
        return try JSONDecoder().decode(Event.self, from: data)
    }

    static func decodeAll(content: String) throws -> [Event] {
        var out: [Event] = []
        for raw in content.split(whereSeparator: { $0.isNewline }) {
            let str = String(raw).trimmingCharacters(in: .whitespaces)
            if str.isEmpty { continue }
            if let event = try? decode(line: str) {
                out.append(event)
            }
        }
        return out
    }

    static func eventsDir() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ccfocus/events", isDirectory: true)
    }

    static func jsonlFilesSortedAsc() throws -> [URL] {
        let dir = eventsDir()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
