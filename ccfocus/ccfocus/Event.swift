import Foundation

struct Event: Decodable {
    let ts: String
    let kind: Kind

    enum Kind {
        case sessionStart(SessionStart)
        case notification(Notification)
        case stop(String)
        case preToolUse(PreToolUse)
        case userPromptSubmit(String)
    }

    struct SessionStart: Decodable {
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

    struct Notification: Decodable {
        let sessionId: String
        let message: String
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case message
        }
    }

    struct PreToolUse: Decodable {
        let sessionId: String
        let tool: String?
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case tool
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ts
        case event
        case session_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ts = try c.decode(String.self, forKey: .ts)
        let tagRaw = try c.decode(String.self, forKey: .event)
        let single = try decoder.singleValueContainer()
        switch tagRaw {
        case "session_start":
            self.kind = .sessionStart(try single.decode(SessionStart.self))
        case "notification":
            self.kind = .notification(try single.decode(Notification.self))
        case "stop":
            let s = try c.decode(String.self, forKey: .session_id)
            self.kind = .stop(s)
        case "pre_tool_use":
            self.kind = .preToolUse(try single.decode(PreToolUse.self))
        case "user_prompt_submit":
            let s = try c.decode(String.self, forKey: .session_id)
            self.kind = .userPromptSubmit(s)
        default:
            throw DecodingError.dataCorruptedError(forKey: .event, in: c, debugDescription: "unknown event: \(tagRaw)")
        }
    }
}
