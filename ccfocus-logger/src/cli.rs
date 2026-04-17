use crate::commands;
use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ccfocus-logger", version, about = "Claude Code hook logger for Ghostty pane tracking")]
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
    Install,
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
            Command::SessionStart => commands::session_start::run(),
            Command::Notification => commands::notification::run(),
            Command::Stop => commands::stop::run(),
            Command::PreToolUse => commands::pre_tool_use::run(),
            Command::UserPromptSubmit => commands::user_prompt_submit::run(),
            Command::Install => commands::install::run(),
        }
    }
}
