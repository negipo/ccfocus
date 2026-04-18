import Foundation

enum SessionStatus: String, Equatable {
    case idle
    case running
    case waitingInput = "waiting_input"
    case done
    case error
    case stale
    case deceased
}

enum EventTransitionKind {
    case sessionStart
    case notification
    case preToolUse
    case stop
    case userPromptSubmit
}

extension SessionStatus {
    static func transitioned(current: SessionStatus?, event: EventTransitionKind) -> SessionStatus {
        if current == .deceased { return .deceased }
        switch (current, event) {
        case (_, .sessionStart): return .idle
        case (_, .notification): return .waitingInput
        case (_, .preToolUse): return .running
        case (_, .stop): return .done
        case (_, .userPromptSubmit): return .running
        }
    }
}
