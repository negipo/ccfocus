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

    mutating func apply(_ ev: Event) {
        switch ev.kind {
        case .sessionStart(let s):
            if let pid = s.claudePid, let st = s.claudeStartTime {
                for (oldSid, old) in sessions where oldSid != s.sessionId
                    && old.claudePid == pid && old.claudeStartTime == st
                    && old.status != .deceased {
                    mutate(oldSid) { $0.status = .deceased; $0.deceasedReason = .claudeTerminated }
                }
            }
            let entry = SessionEntry(
                sessionId: s.sessionId,
                terminalId: s.terminalId,
                cwd: s.cwd,
                gitBranch: s.gitBranch,
                claudePid: s.claudePid,
                claudeStartTime: s.claudeStartTime,
                claudeComm: s.claudeComm,
                status: .idle,
                lastEventTs: ev.ts,
                lastMessage: nil,
                deceasedReason: nil,
                startedAt: ev.ts
            )
            sessions[s.sessionId] = entry
        case .notification(let n):
            mutate(n.sessionId) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .notification)
                e.lastEventTs = ev.ts
                e.lastMessage = n.message
            }
        case .stop(let sid, _):
            mutate(sid) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .stop)
                e.lastEventTs = ev.ts
                e.doneNotified = true
            }
        case .preToolUse(let p):
            mutate(p.sessionId) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .preToolUse)
                e.lastEventTs = ev.ts
            }
        case .userPromptSubmit(let sid):
            mutate(sid) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .userPromptSubmit)
                e.lastEventTs = ev.ts
            }
        }
    }

    mutating func clearMessage(_ sid: String) {
        mutate(sid) { $0.lastMessage = nil }
    }

    mutating func clearDoneNotified(_ sid: String) {
        mutate(sid) { $0.doneNotified = false }
    }

    mutating func mutate(_ sid: String, _ f: (inout SessionEntry) -> Void) {
        guard var e = sessions[sid] else { return }
        f(&e)
        sessions[sid] = e
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
    mutating func markDeceased(sid: String, reason: DeceasedReason) {
        mutate(sid) { e in
            e.status = .deceased
            e.deceasedReason = reason
        }
    }

    mutating func applyStaleAfter(_ now: Date) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (sid, e) in sessions {
            guard let d = fmt.date(from: e.lastEventTs) else { continue }
            let age = now.timeIntervalSince(d)
            if e.status == .idle || e.status == .running || e.status == .waitingInput || e.status == .done {
                if age >= 30 * 60 { mutate(sid) { $0.status = .stale } }
            }
            if e.status == .stale && e.claudePid == nil && age >= 2.5 * 3600 {
                mutate(sid) { $0.status = .deceased; $0.deceasedReason = .timeout }
            }
        }
    }
}
