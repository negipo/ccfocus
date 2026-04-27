use crate::event::{Event, EventKind};
use crate::git::CommandRunner;
use std::collections::HashMap;
use std::path::Path;
use time::{Date, OffsetDateTime, UtcOffset};

const RECENT_DAYS: u8 = 8;

#[derive(Debug, Clone)]
struct Claim {
    ts: String,
    terminal_id: String,
    claude_pid: u32,
    claude_start_time: String,
    claude_comm: String,
}

pub fn collect_live_claims(
    runner: &impl CommandRunner,
    dir: &Path,
) -> HashMap<(u32, String), String> {
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

    if latest.is_empty() {
        return HashMap::new();
    }

    let unique_pids: Vec<u32> = {
        let mut pids: Vec<u32> = latest.keys().map(|(pid, _)| *pid).collect();
        pids.sort_unstable();
        pids.dedup();
        pids
    };
    let live = query_live_processes(runner, &unique_pids);

    let mut claims = HashMap::new();
    for (key, claim) in latest {
        let Some((lstart, comm)) = live.get(&claim.claude_pid) else {
            continue;
        };
        if lstart == &claim.claude_start_time && comm == &claim.claude_comm {
            claims.insert(key, claim.terminal_id);
        }
    }
    claims
}

fn query_live_processes(
    runner: &impl CommandRunner,
    pids: &[u32],
) -> HashMap<u32, (String, String)> {
    if pids.is_empty() {
        return HashMap::new();
    }
    let pid_csv = pids
        .iter()
        .map(|p| p.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let Ok(out) = runner.run("ps", &["-p", &pid_csv, "-o", "pid=,lstart=,comm="]) else {
        return HashMap::new();
    };
    parse_ps_batch(&out)
}

fn parse_ps_batch(out: &str) -> HashMap<u32, (String, String)> {
    let mut map = HashMap::new();
    for line in out.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts.len() < 7 {
            continue;
        }
        let Ok(pid) = parts[0].parse::<u32>() else {
            continue;
        };
        let lstart = parts[1..6].join(" ");
        let comm = parts[6..].join(" ");
        map.insert(pid, (lstart, comm));
    }
    map
}

fn recent_dates() -> Vec<Date> {
    let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
    let now = OffsetDateTime::now_utc().to_offset(offset);
    let today = now.date();
    let mut dates = Vec::with_capacity(RECENT_DAYS as usize);
    let mut cursor = today;
    dates.push(cursor);
    for _ in 1..RECENT_DAYS {
        let Some(prev) = cursor.previous_day() else {
            break;
        };
        cursor = prev;
        dates.push(cursor);
    }
    dates.reverse();
    dates
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

        fn set(&self, pid_csv: &str, resp: std::result::Result<String, String>) {
            self.responses.borrow_mut().insert(pid_csv.to_string(), resp);
        }
    }

    impl CommandRunner for PsRunner {
        fn run(&self, prog: &str, args: &[&str]) -> Result<String> {
            assert_eq!(prog, "ps");
            assert_eq!(args[0], "-p");
            let pid_csv = args[1].to_string();
            let map = self.responses.borrow();
            match map.get(&pid_csv) {
                Some(Ok(s)) => Ok(s.clone()),
                Some(Err(e)) => anyhow::bail!("{}", e),
                None => anyhow::bail!("no stub for {}", pid_csv),
            }
        }
    }

    fn write_today(dir: &Path, content: &str) -> PathBuf {
        let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
        let now = OffsetDateTime::now_utc().to_offset(offset);
        let date = now.date();
        write_dated(dir, date, content)
    }

    fn write_dated(dir: &Path, date: Date, content: &str) -> PathBuf {
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
    fn returns_claim_when_ps_matches() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        let expected: HashMap<(u32, String), String> = HashMap::from([
            ((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string()),
        ]);
        assert_eq!(claims, expected);
    }

    #[test]
    fn drops_claim_when_ps_mismatches() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Sat Apr 18 21:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        assert!(claims.is_empty());
    }

    #[test]
    fn drops_claim_when_ps_fails() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Err("no such process".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        assert!(claims.is_empty());
    }

    #[test]
    fn latest_terminal_id_wins_for_duplicate_pid_start() {
        let tmp = TempDir::new().unwrap();
        let older = r#"{"ts":"2026-04-18T10:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T_OLD","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        let newer = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T_NEW","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{older}\n{newer}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        let expected: HashMap<(u32, String), String> = HashMap::from([
            ((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T_NEW".to_string()),
        ]);
        assert_eq!(claims, expected);
    }

    #[test]
    fn ignores_null_terminal_id() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":null,"cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{line}\n"));
        let runner = PsRunner::new();
        let claims = collect_live_claims(&runner, tmp.path());
        assert!(claims.is_empty());
    }

    #[test]
    fn skips_malformed_lines_but_picks_up_valid() {
        let tmp = TempDir::new().unwrap();
        let garbage = "this is not json";
        let valid = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{garbage}\n{valid}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        let expected: HashMap<(u32, String), String> = HashMap::from([
            ((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string()),
        ]);
        assert_eq!(claims, expected);
    }

    #[test]
    fn returns_empty_when_dir_missing() {
        let runner = PsRunner::new();
        let claims = collect_live_claims(&runner, Path::new("/nonexistent/ccfocus/path"));
        assert!(claims.is_empty());
    }

    #[test]
    fn recent_dates_returns_eight_days_descending_to_today() {
        let dates = recent_dates();
        assert_eq!(dates.len(), 8);
        let last = *dates.last().unwrap();
        let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
        let today = OffsetDateTime::now_utc().to_offset(offset).date();
        assert_eq!(last, today);
        for window in dates.windows(2) {
            let prev = window[0];
            let next = window[1];
            assert_eq!(prev.next_day().unwrap(), next);
        }
    }

    #[test]
    fn collects_claims_from_seven_days_back() {
        let tmp = TempDir::new().unwrap();
        let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
        let today = OffsetDateTime::now_utc().to_offset(offset).date();
        let mut seven_days_ago = today;
        for _ in 0..7 {
            seven_days_ago = seven_days_ago.previous_day().unwrap();
        }
        let line = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        write_dated(tmp.path(), seven_days_ago, &format!("{line}\n"));
        let runner = PsRunner::new();
        runner.set("111", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        let expected: HashMap<(u32, String), String> = HashMap::from([
            ((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string()),
        ]);
        assert_eq!(claims, expected);
    }

    #[test]
    fn batch_ps_returns_subset_alive() {
        let tmp = TempDir::new().unwrap();
        let alive = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/foo","git_branch":null,"claude_pid":111,"claude_start_time":"Fri Apr 18 20:00:00 2026","claude_comm":"claude"}"#;
        let dead = r#"{"ts":"2026-04-18T12:00:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T2","cwd":"/bar","git_branch":null,"claude_pid":222,"claude_start_time":"Fri Apr 18 21:00:00 2026","claude_comm":"claude"}"#;
        write_today(tmp.path(), &format!("{alive}\n{dead}\n"));
        let runner = PsRunner::new();
        runner.set("111,222", Ok("111 Fri Apr 18 20:00:00 2026 claude\n".into()));
        let claims = collect_live_claims(&runner, tmp.path());
        let expected: HashMap<(u32, String), String> = HashMap::from([
            ((111u32, "Fri Apr 18 20:00:00 2026".to_string()), "T1".to_string()),
        ]);
        assert_eq!(claims, expected);
    }

    #[test]
    fn parse_ps_batch_skips_short_lines() {
        let out = "111 Fri Apr 18 20:00:00 2026 claude\nshort line\n222 Sat Apr 19 21:00:00 2026 zsh\n";
        let parsed = parse_ps_batch(out);
        assert_eq!(parsed.len(), 2);
        assert_eq!(
            parsed.get(&111),
            Some(&("Fri Apr 18 20:00:00 2026".to_string(), "claude".to_string()))
        );
        assert_eq!(
            parsed.get(&222),
            Some(&("Sat Apr 19 21:00:00 2026".to_string(), "zsh".to_string()))
        );
    }
}
