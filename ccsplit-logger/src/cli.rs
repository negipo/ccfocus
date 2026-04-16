use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ccsplit-logger", version, about = "Claude Code hook logger for Ghostty pane tracking")]
pub struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    SessionStart,
    Notification,
    Stop,
    PreToolUse,
    UserPromptSubmit,
}

impl Cli {
    pub fn run(self) -> Result<()> {
        match self.command {
            Command::SessionStart => Ok(()),
            Command::Notification => Ok(()),
            Command::Stop => Ok(()),
            Command::PreToolUse => Ok(()),
            Command::UserPromptSubmit => Ok(()),
        }
    }
}
