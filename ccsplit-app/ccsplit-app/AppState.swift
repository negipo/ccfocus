import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var registry = SessionRegistry()
    private let reader = LogTail.Reader()
    private var watcher: LogTail.Watcher?

    func bootstrap() {
        replayAllJsonl()
        startWatching()
    }

    private func replayAllJsonl() {
        let files = (try? EventLogReader.jsonlFilesSortedAsc()) ?? []
        for f in files {
            let lines = reader.readNew(url: f)
            for line in lines {
                if let ev = try? EventLogReader.decode(line: line) {
                    registry.apply(ev)
                }
            }
        }
    }

    private func startWatching() {
        let dir = EventLogReader.eventsDir().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        watcher = LogTail.Watcher(directory: dir) { [weak self] in
            self?.onFsEvent()
        }
        watcher?.start()
    }

    private func onFsEvent() {
        let files = (try? EventLogReader.jsonlFilesSortedAsc()) ?? []
        var appliedAny = false
        for f in files {
            let lines = reader.readNew(url: f)
            for line in lines {
                if let ev = try? EventLogReader.decode(line: line) {
                    registry.apply(ev)
                    appliedAny = true
                }
            }
        }
        if appliedAny { objectWillChange.send() }
    }
}
