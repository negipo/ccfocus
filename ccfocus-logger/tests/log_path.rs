use ccfocus_logger::log_path::{events_dir, log_file_for};
use time::macros::date;

#[test]
fn events_dir_is_application_support_ccfocus_events() {
    let home = std::env::var("HOME").unwrap();
    let dir = events_dir().unwrap();
    assert_eq!(
        dir,
        std::path::PathBuf::from(format!(
            "{}/Library/Application Support/ccfocus/events",
            home
        ))
    );
}

#[test]
fn log_file_for_uses_yyyy_mm_dd_jsonl() {
    let d = date!(2026 - 04 - 16);
    let p = log_file_for(d).unwrap();
    let s = p.to_string_lossy();
    assert!(s.ends_with("events/2026-04-16.jsonl"));
}
