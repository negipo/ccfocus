use ccsplit_logger::event::{Event, EventKind};
use ccsplit_logger::log_writer::append_event_to;
use tempfile::tempdir;

#[test]
fn append_creates_file_with_single_line() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("2026-04-16.jsonl");
    let ev = Event {
        ts: "2026-04-16T00:00:00.000Z".to_string(),
        kind: EventKind::Stop {
            session_id: "abc".to_string(),
        },
    };
    append_event_to(&path, &ev).unwrap();
    let content = std::fs::read_to_string(&path).unwrap();
    assert_eq!(content.lines().count(), 1);
    assert!(content.ends_with('\n'));
}

#[test]
fn append_two_events_produces_two_lines() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("d.jsonl");
    for sid in ["a", "b"] {
        let ev = Event {
            ts: "2026-04-16T00:00:00.000Z".to_string(),
            kind: EventKind::Stop {
                session_id: sid.to_string(),
            },
        };
        append_event_to(&path, &ev).unwrap();
    }
    let content = std::fs::read_to_string(&path).unwrap();
    assert_eq!(content.lines().count(), 2);
}

#[test]
fn append_creates_parent_dir_if_missing() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("nested/deeper/file.jsonl");
    let ev = Event {
        ts: "2026-04-16T00:00:00.000Z".to_string(),
        kind: EventKind::Stop {
            session_id: "abc".to_string(),
        },
    };
    append_event_to(&path, &ev).unwrap();
    assert!(path.exists());
}
