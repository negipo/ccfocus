use anyhow::{anyhow, Result};
use std::path::PathBuf;
use time::{Date, OffsetDateTime, UtcOffset};

pub fn events_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").map_err(|_| anyhow!("HOME not set"))?;
    Ok(PathBuf::from(home).join("Library/Application Support/ccfocus/events"))
}

pub fn log_file_for(date: Date) -> Result<PathBuf> {
    let name = format!(
        "{:04}-{:02}-{:02}.jsonl",
        date.year(),
        u8::from(date.month()),
        date.day()
    );
    Ok(events_dir()?.join(name))
}

pub fn log_file_for_now() -> Result<PathBuf> {
    let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
    let now = OffsetDateTime::now_utc().to_offset(offset);
    log_file_for(now.date())
}
