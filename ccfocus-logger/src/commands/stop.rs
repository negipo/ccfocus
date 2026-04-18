use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;

#[derive(Debug, Deserialize)]
struct Payload {
    session_id: String,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::Stop {
            session_id: p.session_id,
            has_question: None,
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
