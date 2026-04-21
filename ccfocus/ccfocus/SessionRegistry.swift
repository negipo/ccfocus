import Foundation

enum DeceasedReason { case claudeTerminated; case paneClosed; case timeout }

struct SessionEntry: Identifiable {
    var id: String { sessionId }
    let sessionId: String
    var terminalId: String?
    var cwd: String
    var gitBranch: String?
    var claudePid: UInt32?
    var claudeStartTime: String?
    var claudeComm: String?
    var status: SessionStatus
    var lastEventTs: String
    var lastMessage: String?
    var deceasedReason: DeceasedReason?
    var startedAt: String
    var doneNotified: Bool = false
}

struct SessionRegistry {
    var sessions: [String: SessionEntry] = [:]

    mutating func apply(_ event: Event) {
        switch event.kind {
        case .sessionStart(let start):
            if let pid = start.claudePid, let startTime = start.claudeStartTime {
                for (oldSid, old) in sessions where oldSid != start.sessionId
                    && old.claudePid == pid && old.claudeStartTime == startTime
                    && old.status != .deceased {
                    mutate(oldSid) { $0.status = .deceased; $0.deceasedReason = .claudeTerminated }
                }
            }
            let entry = SessionEntry(
                sessionId: start.sessionId,
                terminalId: start.terminalId,
                cwd: start.cwd,
                gitBranch: start.gitBranch,
                claudePid: start.claudePid,
                claudeStartTime: start.claudeStartTime,
                claudeComm: start.claudeComm,
                status: .idle,
                lastEventTs: event.timestamp,
                lastMessage: nil,
                deceasedReason: nil,
                startedAt: event.timestamp
            )
            sessions[start.sessionId] = entry
        case .notification(let notif):
            mutate(notif.sessionId) { entry in
                entry.status = SessionStatus.transitioned(current: entry.status, event: .notification)
                entry.lastEventTs = event.timestamp
                entry.lastMessage = notif.message
            }
        case .stop(let sid, let hasQuestion):
            mutate(sid) { entry in
                let kind: EventTransitionKind = hasQuestion == true ? .stopWithQuestion : .stop
                entry.status = SessionStatus.transitioned(current: entry.status, event: kind)
                entry.lastEventTs = event.timestamp
                entry.doneNotified = hasQuestion != true
            }
        case .preToolUse(let pre):
            mutate(pre.sessionId) { entry in
                entry.status = SessionStatus.transitioned(current: entry.status, event: .preToolUse)
                entry.lastEventTs = event.timestamp
            }
        case .userPromptSubmit(let sid):
            mutate(sid) { entry in
                entry.status = SessionStatus.transitioned(current: entry.status, event: .userPromptSubmit)
                entry.lastEventTs = event.timestamp
            }
        }
    }

    mutating func clearMessage(_ sid: String) {
        mutate(sid) { $0.lastMessage = nil }
    }

    mutating func clearDoneNotified(_ sid: String) {
        mutate(sid) { $0.doneNotified = false }
    }

    mutating func mutate(_ sid: String, _ transform: (inout SessionEntry) -> Void) {
        guard var entry = sessions[sid] else { return }
        transform(&entry)
        sessions[sid] = entry
    }

    func sortedByLastEventDesc() -> [SessionEntry] {
        sessions.values.sorted {
            if ($0.status == .deceased) != ($1.status == .deceased) {
                return $1.status == .deceased
            }
            return $0.lastEventTs > $1.lastEventTs
        }
    }
}

extension SessionRegistry {
    var attentionCount: Int {
        sessions.values.reduce(into: 0) { count, entry in
            switch entry.status {
            case .asking, .waitingInput, .done, .idle, .error:
                count += 1
            case .running, .stale, .deceased:
                break
            }
        }
    }

    mutating func markDeceased(sid: String, reason: DeceasedReason) {
        mutate(sid) { entry in
            entry.status = .deceased
            entry.deceasedReason = reason
        }
    }

    mutating func applyStaleAfter(_ now: Date) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (sid, entry) in sessions {
            guard let date = fmt.date(from: entry.lastEventTs) else { continue }
            let age = now.timeIntervalSince(date)
            let activeStatuses: [SessionStatus] = [.idle, .running, .asking, .waitingInput, .done]
            if activeStatuses.contains(entry.status) {
                if age >= 30 * 60 { mutate(sid) { $0.status = .stale } }
            }
            if entry.status == .stale && entry.claudePid == nil && age >= 2.5 * 3600 {
                mutate(sid) { $0.status = .deceased; $0.deceasedReason = .timeout }
            }
        }
    }
}
