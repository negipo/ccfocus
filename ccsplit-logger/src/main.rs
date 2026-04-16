use anyhow::Result;
use clap::Parser;
use ccsplit_logger::cli::Cli;
use ccsplit_logger::detach::{become_session_leader, detach_and_exit_parent, is_detached_child};

fn main() -> Result<()> {
    let cli = Cli::parse();
    if cli.needs_detach() {
        if !is_detached_child() {
            detach_and_exit_parent()?;
            unreachable!();
        }
        become_session_leader();
    }
    cli.run()
}
