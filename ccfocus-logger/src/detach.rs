use crate::claude_proc::find_claude_proc;
use crate::git::RealRunner;
use anyhow::Result;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

pub const CHILD_ENV: &str = "CCFOCUS_LOGGER_DETACHED";

pub fn child_env_marker() -> &'static str {
    CHILD_ENV
}

pub fn is_detached_child() -> bool {
    std::env::var(CHILD_ENV).is_ok()
}

pub fn detach_and_exit_parent() -> Result<()> {
    let mut payload = Vec::new();
    std::io::stdin().read_to_end(&mut payload)?;

    let exe = std::env::current_exe()?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut cmd = Command::new(exe);
    cmd.args(&args)
        .env(CHILD_ENV, "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let ppid = parent_pid();
    if let Some(info) = find_claude_proc(&RealRunner, ppid, 5) {
        cmd.env("CCFOCUS_CLAUDE_PID", info.pid.to_string())
            .env("CCFOCUS_CLAUDE_START", &info.lstart)
            .env("CCFOCUS_CLAUDE_COMM", &info.comm);
    }

    let mut child = cmd.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(&payload)?;
    }
    std::process::exit(0);
}

#[cfg(unix)]
pub fn become_session_leader() {
    extern "C" {
        fn setsid() -> i32;
    }
    unsafe {
        let _ = setsid();
    }
}

#[cfg(unix)]
fn parent_pid() -> u32 {
    extern "C" {
        fn getppid() -> i32;
    }
    unsafe { getppid() as u32 }
}
