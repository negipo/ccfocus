use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use crate::transcript::{classify_has_question, last_assistant_text};
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
struct Payload {
    session_id: String,
    #[serde(default)]
    transcript_path: Option<PathBuf>,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let has_question = p
        .transcript_path
        .as_deref()
        .and_then(last_assistant_text)
        .map(|t| classify_has_question(&t));
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::Stop {
            session_id: p.session_id,
            has_question,
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
