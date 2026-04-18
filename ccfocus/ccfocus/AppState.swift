import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var registry = SessionRegistry()
    @Published private(set) var pairings = ManualPairingsStore(fileURL: ManualPairingsStore.defaultURL())
    @Published var manualPairingSession: SessionEntry?
    @Published private(set) var cachedTerminals: [GhosttyTerminalInfo] = []
    private let reader = LogTail.Reader()
    private var watcher: LogTail.Watcher?
    private var livenessTimer: Timer?
    private var rotationTimer: Timer?
    private var bootstrapDone = false
    var onOpenPopover: (() -> Void)?

    func bootstrap() {
        LogRotator.rotate(directory: EventLogReader.eventsDir(), now: Date(), retentionDays: 7)
        try? pairings.load()
        replayAllJsonl()
        startWatching()
        runLivenessCheck()
        startLivenessTimer()
        startRotationTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.bootstrapDone = true
        }
    }

    func clearMessage(_ sessionId: String) {
        registry.clearMessage(sessionId)
        objectWillChange.send()
    }

    func clearDoneNotified(_ sessionId: String) {
        registry.clearDoneNotified(sessionId)
        objectWillChange.send()
    }

    func setManualPairing(sessionId: String, terminalId: String) {
        pairings.set(sessionId: sessionId, terminalId: terminalId)
        try? pairings.save()
        objectWillChange.send()
    }

    func effectiveTerminalId(for entry: SessionEntry) -> String? {
        entry.terminalId ?? pairings.get(sessionId: entry.sessionId)
    }

    func presentManualPair(for entry: SessionEntry) {
        cachedTerminals = GhosttyFocus.listTerminals()
        manualPairingSession = entry
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
        watcher?.stop()
        let dir = EventLogReader.eventsDir().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        watcher = LogTail.Watcher(directory: dir) { [weak self] in
            MainActor.assumeIsolated {
                self?.onFsEvent()
            }
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
                    if bootstrapDone {
                        if case .notification(let n) = ev.kind,
                           let entry = registry.sessions[n.sessionId],
                           entry.status == .waitingInput {
                            onOpenPopover?()
                        }
                        if case .stop(let sid, _) = ev.kind,
                           let entry = registry.sessions[sid],
                           (entry.status == .done || entry.status == .asking) {
                            onOpenPopover?()
                        }
                    }
                }
            }
        }
        if appliedAny { objectWillChange.send() }
    }

    private func startLivenessTimer() {
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runLivenessCheck() }
        }
    }

    private func startRotationTimer() {
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                LogRotator.rotate(directory: EventLogReader.eventsDir(), now: Date(), retentionDays: 7)
                self?.objectWillChange.send()
            }
        }
    }

    private func runLivenessCheck() {
        let terms = LivenessChecker.ghosttyTerminalIds()
        for (sid, e) in registry.sessions {
            if [.idle, .running, .asking, .waitingInput, .done, .stale].contains(e.status) == false { continue }
            if let pid = e.claudePid, let st = e.claudeStartTime, let cm = e.claudeComm {
                if let cur = LivenessChecker.queryPs(pid: pid) {
                    if !LivenessChecker.verify(expected: (pid, st, cm), current: cur) {
                        registry.markDeceased(sid: sid, reason: .claudeTerminated)
                        continue
                    }
                } else {
                    registry.markDeceased(sid: sid, reason: .claudeTerminated)
                    continue
                }
            }
            if let tid = e.terminalId, !terms.contains(tid) {
                registry.markDeceased(sid: sid, reason: .paneClosed)
            }
        }
        registry.applyStaleAfter(Date())
        if LivenessChecker.cleanupPairings(store: &pairings, liveTerminals: terms) {
            try? pairings.save()
        }
        objectWillChange.send()
    }
}
