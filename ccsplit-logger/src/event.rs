use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub ts: String,
    #[serde(flatten)]
    pub kind: EventKind,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum EventKind {
    SessionStart {
        session_id: String,
        terminal_id: Option<String>,
        cwd: String,
        git_branch: Option<String>,
        claude_pid: Option<u32>,
        claude_start_time: Option<String>,
        claude_comm: Option<String>,
    },
    Notification {
        session_id: String,
        message: String,
    },
    Stop {
        session_id: String,
    },
    PreToolUse {
        session_id: String,
        tool: Option<String>,
    },
    UserPromptSubmit {
        session_id: String,
    },
}
