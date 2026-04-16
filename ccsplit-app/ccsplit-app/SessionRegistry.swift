import Foundation

struct SessionEntry {
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
    var startedAt: String
}

struct SessionRegistry {
    var sessions: [String: SessionEntry] = [:]

    mutating func apply(_ ev: Event) {
        switch ev.kind {
        case .sessionStart(let s):
            let entry = SessionEntry(
                sessionId: s.sessionId,
                terminalId: s.terminalId,
                cwd: s.cwd,
                gitBranch: s.gitBranch,
                claudePid: s.claudePid,
                claudeStartTime: s.claudeStartTime,
                claudeComm: s.claudeComm,
                status: .running,
                lastEventTs: ev.ts,
                lastMessage: nil,
                startedAt: ev.ts
            )
            sessions[s.sessionId] = entry
        case .notification(let n):
            mutate(n.sessionId) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .notification)
                e.lastEventTs = ev.ts
                e.lastMessage = n.message
            }
        case .stop(let sid):
            mutate(sid) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .stop)
                e.lastEventTs = ev.ts
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

    private mutating func mutate(_ sid: String, _ f: (inout SessionEntry) -> Void) {
        guard var e = sessions[sid] else { return }
        f(&e)
        sessions[sid] = e
    }

    func sortedByLastEventDesc() -> [SessionEntry] {
        sessions.values.sorted { $0.lastEventTs > $1.lastEventTs }
    }
}
