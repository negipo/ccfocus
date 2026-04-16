use crate::event::Event;
use anyhow::{Context, Result};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::Path;

pub fn append_event_to(path: &Path, ev: &Event) -> Result<()> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent).with_context(|| format!("mkdir -p {}", parent.display()))?;
    }
    let mut f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("open {}", path.display()))?;
    let line = serde_json::to_string(ev)?;
    f.write_all(line.as_bytes())?;
    f.write_all(b"\n")?;
    Ok(())
}
