use crate::event::{Event, EventKind};
use crate::ghostty::find_terminal_id_with_retry;
use crate::git::{git_branch, RealRunner};
use crate::log_path::{events_dir, log_file_for_now};
use crate::log_reader::collect_live_claims;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::time::Duration;

#[derive(Debug, Deserialize)]
pub struct HookPayload {
    pub session_id: String,
    pub cwd: String,
}

pub fn inherit_terminal_id(
    claims: &HashMap<(u32, String), String>,
    claude_pid: Option<u32>,
    claude_start_time: Option<&str>,
) -> Option<String> {
    let (Some(pid), Some(start)) = (claude_pid, claude_start_time) else {
        return None;
    };
    claims.get(&(pid, start.to_string())).cloned()
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let payload: HookPayload = serde_json::from_str(&buf)?;

    let claude_pid = std::env::var("CCFOCUS_CLAUDE_PID")
        .ok()
        .and_then(|s| s.parse().ok());
    let claude_start_time = std::env::var("CCFOCUS_CLAUDE_START").ok();
    let claude_comm = std::env::var("CCFOCUS_CLAUDE_COMM").ok();

    let runner = RealRunner;
    let claims = match events_dir() {
        Ok(dir) => collect_live_claims(&runner, &dir),
        Err(_) => HashMap::new(),
    };
    let inherited = inherit_terminal_id(&claims, claude_pid, claude_start_time.as_deref());
    let terminal_id = match inherited {
        Some(id) => Some(id),
        None => {
            let claimed: HashSet<String> = claims.values().cloned().collect();
            find_terminal_id_with_retry(
                &runner,
                &payload.cwd,
                &claimed,
                5,
                Duration::from_millis(100),
            )
        }
    };
    let git_branch = git_branch(&runner, &payload.cwd).unwrap_or(None);

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

    #[test]
    fn inherit_returns_existing_terminal_for_matching_claim() {
        let mut claims = std::collections::HashMap::new();
        claims.insert((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string());
        let got = super::inherit_terminal_id(
            &claims,
            Some(111),
            Some("Fri Apr 18 20:00:00 2026"),
        );
        assert_eq!(got, Some("T1".to_string()));
    }

    #[test]
    fn inherit_returns_none_when_claim_missing() {
        let mut claims = std::collections::HashMap::new();
        claims.insert((222u32, "Fri Apr 18 21:00:00 2026".to_string()), "T2".to_string());
        let got = super::inherit_terminal_id(
            &claims,
            Some(111),
            Some("Fri Apr 18 20:00:00 2026"),
        );
        assert_eq!(got, None);
    }

    #[test]
    fn inherit_returns_none_when_pid_missing() {
        let mut claims = std::collections::HashMap::new();
        claims.insert((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string());
        let got = super::inherit_terminal_id(
            &claims,
            None,
            Some("Fri Apr 18 20:00:00 2026"),
        );
        assert_eq!(got, None);
    }

    #[test]
    fn inherit_returns_none_when_start_missing() {
        let mut claims = std::collections::HashMap::new();
        claims.insert((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string());
        let got = super::inherit_terminal_id(&claims, Some(111), None);
        assert_eq!(got, None);
    }
}
