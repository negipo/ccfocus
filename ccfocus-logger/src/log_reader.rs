use crate::event::{Event, EventKind};
use crate::git::CommandRunner;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use time::{Date, OffsetDateTime, UtcOffset};

#[derive(Debug, Clone)]
struct Claim {
    ts: String,
    terminal_id: String,
    claude_pid: u32,
    claude_start_time: String,
    claude_comm: String,
}

pub fn collect_live_claimed_terminal_ids(
    runner: &impl CommandRunner,
    dir: &Path,
) -> HashSet<String> {
    let dates = recent_dates();
    let mut latest: HashMap<(u32, String), Claim> = HashMap::new();

    for date in &dates {
        let path = dir.join(format!(
            "{:04}-{:02}-{:02}.jsonl",
            date.year(),
            u8::from(date.month()),
            date.day()
        ));
        let Ok(content) = std::fs::read_to_string(&path) else {
            continue;
        };
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let Ok(ev) = serde_json::from_str::<Event>(trimmed) else {
                continue;
            };
            let EventKind::SessionStart {
                terminal_id,
                claude_pid,
                claude_start_time,
                claude_comm,
                ..
            } = ev.kind
            else {
                continue;
            };
            let (Some(terminal_id), Some(pid), Some(start), Some(comm)) =
                (terminal_id, claude_pid, claude_start_time, claude_comm)
            else {
                continue;
            };
            let key = (pid, start.clone());
            let claim = Claim {
                ts: ev.ts,
                terminal_id,
                claude_pid: pid,
                claude_start_time: start,
                claude_comm: comm,
            };
            match latest.get(&key) {
                Some(existing) if existing.ts >= claim.ts => {}
                _ => {
                    latest.insert(key, claim);
                }
            }
        }
    }

    let mut claimed = HashSet::new();
    for claim in latest.values() {
        if is_alive(runner, claim) {
            claimed.insert(claim.terminal_id.clone());
        }
    }
    claimed
}

fn is_alive(runner: &impl CommandRunner, claim: &Claim) -> bool {
    let pid_str = claim.claude_pid.to_string();
    let Ok(out) = runner.run("ps", &["-p", &pid_str, "-o", "pid=,lstart=,comm="]) else {
        return false;
    };
    let trimmed = out.trim();
    if trimmed.is_empty() {
        return false;
    }
    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    if parts.len() < 7 {
        return false;
    }
    let Ok(pid) = parts[0].parse::<u32>() else {
        return false;
    };
    if pid != claim.claude_pid {
        return false;
    }
    let lstart = parts[1..6].join(" ");
    let comm = parts[6..].join(" ");
    lstart == claim.claude_start_time && comm == claim.claude_comm
}

fn recent_dates() -> Vec<Date> {
    let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
    let now = OffsetDateTime::now_utc().to_offset(offset);
    let today = now.date();
    let yesterday = today.previous_day().unwrap_or(today);
    vec![yesterday, today]
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::Result;
    use std::cell::RefCell;
    use std::path::PathBuf;
    use tempfile::TempDir;

    struct PsRunner {
        responses: RefCell<HashMap<String, std::result::Result<String, String>>>,
    }

    impl PsRunner {
        fn new() -> Self {
            Self {
                responses: RefCell::new(HashMap::new()),
            }
        }

        fn set(&self, pid: &str, resp: std::result::Result<String, String>) {
            self.responses.borrow_mut().insert(pid.to_string(), resp);
        }
    }

    impl CommandRunner for PsRunner {
        fn run(&self, prog: &str, args: &[&str]) -> Result<String> {
            assert_eq!(prog, "ps");
            assert_eq!(args[0], "-p");
            let pid = args[1].to_string();
            let map = self.responses.borrow();
            match map.get(&pid) {
                Some(Ok(s)) => Ok(s.clone()),
                Some(Err(e)) => anyhow::bail!("{}", e),
                None => anyhow::bail!("no stub for {}", pid),
            }
        }
    }

    fn write_today(dir: &Path, content: &str) -> PathBuf {
        let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
        let now = OffsetDateTime::now_utc().to_offset(offset);
        let date = now.date();
        let name = format!(
            "{:04}-{:02}-{:02}.jsonl",
            date.year(),
            u8::from(date.month()),
            date.day()
        );
        let path = dir.join(name);
        std::fs::write(&path, content).unwrap();
        path
    }

    #[test]
    fn includes_terminal_when_ps_matches() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert_eq!(claimed, HashSet::from(["T1".to_string()]));
    }

    #[test]
    fn drops_claim_when_ps_mismatches() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Sat Apr 18 21:00:00 2026 claude\n".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert!(claimed.is_empty());
    }

    #[test]
    fn drops_claim_when_ps_fails() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Err("no such process".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert!(claimed.is_empty());
    }

    #[test]
    fn latest_terminal_id_wins_for_duplicate_pid_start() {
        let tmp = TempDir::new().unwrap();
        let older = r#"{"ts":"2026-04-18T10:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T_OLD","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        let newer = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T_NEW","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{older}\n{newer}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert_eq!(claimed, HashSet::from(["T_NEW".to_string()]));
    }

    #[test]
    fn ignores_null_terminal_id() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":null,"cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert!(claimed.is_empty());
    }

    #[test]
    fn skips_malformed_lines_but_picks_up_valid() {
        let tmp = TempDir::new().unwrap();
        let garbage = "this is not json";
        let valid = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{garbage}\n{valid}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claimed = collect_live_claimed_terminal_ids(&runner, tmp.path());
        assert_eq!(claimed, HashSet::from(["T1".to_string()]));
    }

    #[test]
    fn returns_empty_when_dir_missing() {
        let runner = PsRunner::new();
        let claimed = collect_live_claimed_terminal_ids(&runner, Path::new("/nonexistent/ccfocus/path"));
        assert!(claimed.is_empty());
    }
}
