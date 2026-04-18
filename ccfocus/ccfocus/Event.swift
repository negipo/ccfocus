import Foundation

struct Event: Decodable {
    let timestamp: String
    let kind: Kind

    enum Kind {
        case sessionStart(SessionStartPayload)
        case notification(NotificationPayload)
        case stop(String, Bool?)
        case preToolUse(PreToolUsePayload)
        case userPromptSubmit(String)
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case event
        case sessionId = "session_id"
        case hasQuestion = "has_question"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        let tagRaw = try container.decode(String.self, forKey: .event)
        let single = try decoder.singleValueContainer()
        switch tagRaw {
        case "session_start":
            self.kind = .sessionStart(try single.decode(SessionStartPayload.self))
        case "notification":
            self.kind = .notification(try single.decode(NotificationPayload.self))
        case "stop":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let hasQuestion = try container.decodeIfPresent(Bool.self, forKey: .hasQuestion)
            self.kind = .stop(sessionId, hasQuestion)
        case "pre_tool_use":
            self.kind = .preToolUse(try single.decode(PreToolUsePayload.self))
        case "user_prompt_submit":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self.kind = .userPromptSubmit(sessionId)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .event,
                in: container,
                debugDescription: "unknown event: \(tagRaw)"
            )
        }
    }
}

struct SessionStartPayload: Decodable {
    let sessionId: String
    let terminalId: String?
    let cwd: String
    let gitBranch: String?
    let claudePid: UInt32?
    let claudeStartTime: String?
    let claudeComm: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case terminalId = "terminal_id"
        case cwd
        case gitBranch = "git_branch"
        case claudePid = "claude_pid"
        case claudeStartTime = "claude_start_time"
        case claudeComm = "claude_comm"
    }
}

struct NotificationPayload: Decodable {
    let sessionId: String
    let message: String
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case message
    }
}

struct PreToolUsePayload: Decodable {
    let sessionId: String
    let tool: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case tool
    }
}
