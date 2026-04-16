use crate::git::CommandRunner;
use anyhow::{anyhow, Result};

pub const CLAUDE_PATTERNS: &[&str] = &["claude", "claude-code"];

#[derive(Debug, Clone)]
pub struct ProcInfo {
    pub pid: u32,
    pub lstart: String,
    pub comm: String,
    pub command: String,
}

pub fn query_proc(runner: &impl CommandRunner, pid: u32) -> Result<ProcInfo> {
    let out = runner.run(
        "ps",
        &[
            "-p",
            &pid.to_string(),
            "-o",
            "pid=,lstart=,comm=,command=",
        ],
    )?;
    parse_ps_line(&out, pid)
}

fn parse_ps_line(s: &str, expected_pid: u32) -> Result<ProcInfo> {
    let line = s.trim_end_matches('\n').trim_start();
    let mut tokens = line.split_whitespace();
    let pid_str = tokens.next().ok_or_else(|| anyhow!("empty ps output"))?;
    let pid: u32 = pid_str.parse()?;
    if pid != expected_pid {
        return Err(anyhow!("pid mismatch"));
    }
    let mut lstart_parts = Vec::new();
    for _ in 0..5 {
        lstart_parts.push(
            tokens
                .next()
                .ok_or_else(|| anyhow!("incomplete lstart"))?,
        );
    }
    let lstart = lstart_parts.join(" ");
    let comm = tokens
        .next()
        .ok_or_else(|| anyhow!("missing comm"))?
        .to_string();
    let command = tokens.collect::<Vec<_>>().join(" ");
    Ok(ProcInfo {
        pid,
        lstart,
        comm,
        command,
    })
}

pub fn is_claude_like(comm: &str, command: &str) -> bool {
    let c = comm.to_ascii_lowercase();
    let full = command.to_ascii_lowercase();
    CLAUDE_PATTERNS.iter().any(|p| {
        let pl = p.to_ascii_lowercase();
        c.contains(&pl) || full.contains(&pl)
    })
}

pub fn find_claude_proc<R: CommandRunner>(
    runner: &R,
    start_pid: u32,
    max_depth: u32,
) -> Option<ProcInfo> {
    let mut pid = start_pid;
    for _ in 0..=max_depth {
        let info = match query_proc(runner, pid) {
            Ok(i) => i,
            Err(_) => return None,
        };
        if is_claude_like(&info.comm, &info.command) {
            return Some(info);
        }
        match ppid_of(runner, pid) {
            Some(p) if p > 0 && p != pid => pid = p,
            _ => return None,
        }
    }
    None
}

fn ppid_of<R: CommandRunner>(runner: &R, pid: u32) -> Option<u32> {
    runner
        .run("ps", &["-p", &pid.to_string(), "-o", "ppid="])
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::git::CommandRunner;

    struct Fake(String);
    impl CommandRunner for Fake {
        fn run(&self, _p: &str, _a: &[&str]) -> anyhow::Result<String> {
            Ok(self.0.clone())
        }
    }

    #[test]
    fn parses_ps_output_with_command() {
        let r = Fake(
            "12345 Wed Apr 16 09:12:34 2026 claude /opt/homebrew/bin/claude --verbose\n".into(),
        );
        let info = query_proc(&r, 12345).unwrap();
        assert_eq!(info.pid, 12345);
        assert_eq!(info.lstart, "Wed Apr 16 09:12:34 2026");
        assert_eq!(info.comm, "claude");
        assert!(info.command.contains("/claude"));
    }

    #[test]
    fn is_claude_like_accepts_claude_comm() {
        assert!(is_claude_like("claude", "claude"));
    }

    #[test]
    fn is_claude_like_accepts_node_with_claude_in_command() {
        assert!(is_claude_like("node", "/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude"));
    }

    #[test]
    fn is_claude_like_rejects_plain_zsh() {
        assert!(!is_claude_like("zsh", "-zsh"));
    }
}
