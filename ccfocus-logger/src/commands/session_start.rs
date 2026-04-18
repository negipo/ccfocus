use crate::event::{Event, EventKind};
use crate::ghostty::find_terminal_id_with_retry;
use crate::git::{git_branch, RealRunner};
use crate::log_path::{events_dir, log_file_for_now};
use crate::log_reader::collect_live_claimed_terminal_ids;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::collections::HashSet;
use std::io::Read;
use std::time::Duration;

#[derive(Debug, Deserialize)]
pub struct HookPayload {
    pub session_id: String,
    pub cwd: String,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let payload: HookPayload = serde_json::from_str(&buf)?;

    let runner = RealRunner;
    let claimed = match events_dir() {
        Ok(dir) => collect_live_claimed_terminal_ids(&runner, &dir),
        Err(_) => HashSet::new(),
    };
    let terminal_id = find_terminal_id_with_retry(
        &runner,
        &payload.cwd,
        &claimed,
        5,
        Duration::from_millis(100),
    );
    let git_branch = git_branch(&runner, &payload.cwd).unwrap_or(None);

    let claude_pid = std::env::var("CCFOCUS_CLAUDE_PID")
        .ok()
        .and_then(|s| s.parse().ok());
    let claude_start_time = std::env::var("CCFOCUS_CLAUDE_START").ok();
    let claude_comm = std::env::var("CCFOCUS_CLAUDE_COMM").ok();

    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::SessionStart {
            session_id: payload.session_id,
            terminal_id,
            cwd: payload.cwd,
            git_branch,
            claude_pid,
            claude_start_time,
            claude_comm,
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::HookPayload;

    #[test]
    fn parses_minimal_session_start_payload() {
        let json = r#"{"session_id":"abc","cwd":"/foo"}"#;
        let p: HookPayload = serde_json::from_str(json).unwrap();
        assert_eq!(p.session_id, "abc");
        assert_eq!(p.cwd, "/foo");
    }

    #[test]
    fn tolerates_extra_fields() {
        let json = r#"{"session_id":"abc","cwd":"/foo","hook_event_name":"SessionStart","extra":123}"#;
        let p: HookPayload = serde_json::from_str(json).unwrap();
        assert_eq!(p.session_id, "abc");
    }
}
