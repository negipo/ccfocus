import Foundation

struct ManualPairingsStore {
    private(set) var map: [String: String] = [:]
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { map = [:]; return }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { map = [:]; return }
        map = (try JSONDecoder().decode([String: String].self, from: data))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(map)
        try data.write(to: fileURL, options: .atomic)
    }

    mutating func set(sessionId: String, terminalId: String) {
        map[sessionId] = terminalId
    }

    func get(sessionId: String) -> String? { map[sessionId] }

    mutating func removePairingsReferring(terminalIds: Set<String>) {
        map = map.filter { !terminalIds.contains($0.value) }
    }

    static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ccsplit/manual_pairings.json")
    }
}
