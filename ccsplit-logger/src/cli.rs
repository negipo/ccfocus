use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ccsplit-logger", version, about = "Claude Code hook logger for Ghostty pane tracking")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    SessionStart,
    Notification,
    Stop,
    PreToolUse,
    UserPromptSubmit,
}

impl Cli {
    pub fn needs_detach(&self) -> bool {
        matches!(
            self.command,
            Command::SessionStart
                | Command::Notification
                | Command::Stop
                | Command::PreToolUse
                | Command::UserPromptSubmit
        )
    }

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
