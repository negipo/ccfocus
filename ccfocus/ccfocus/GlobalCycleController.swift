import Foundation

protocol TerminalFocusing {
    func focus(terminalId: String)
}

struct GhosttyTerminalFocus: TerminalFocusing {
    func focus(terminalId: String) {
        GhosttyFocus.focus(terminalId: terminalId)
    }
}

@MainActor
final class GlobalCycleController {
    private(set) var anchorSessionId: String?
    private let focuser: TerminalFocusing

    init(focuser: TerminalFocusing = GhosttyTerminalFocus()) {
        self.focuser = focuser
    }

    func cycleNext(state: AppState) -> SessionEntry? {
        let candidates = state.registry.sortedByLastEventDesc()
            .filter { $0.status != .deceased }
            .filter { state.effectiveTerminalId(for: $0) != nil }
        guard !candidates.isEmpty else {
            anchorSessionId = nil
            return nil
        }
        let nextIndex: Int
        if let anchor = anchorSessionId,
           let idx = candidates.firstIndex(where: { $0.sessionId == anchor }) {
            nextIndex = (idx + 1) % candidates.count
        } else {
            nextIndex = 0
        }
        let target = candidates[nextIndex]
        anchorSessionId = target.sessionId
        if let tid = state.effectiveTerminalId(for: target) {
            focuser.focus(terminalId: tid)
        }
        return target
    }

    func reset() {
        anchorSessionId = nil
    }
}
