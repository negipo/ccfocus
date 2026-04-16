use anyhow::Result;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

pub const CHILD_ENV: &str = "CCSPLIT_LOGGER_DETACHED";

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
    let mut child = Command::new(exe)
        .args(&args)
        .env(CHILD_ENV, "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
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
