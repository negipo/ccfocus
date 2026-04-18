use ccfocus_logger::event::EventKind;
use ccfocus_logger::transcript::{classify_has_question, last_assistant_text};
use std::io::Write;

#[test]
fn classify_from_sample_transcript_true() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t.jsonl");
    let mut f = std::fs::File::create(&path).unwrap();
    writeln!(
        f,
        r#"{{"type":"assistant","message":{{"content":[{{"type":"text","text":"次はどちらで進めますか?"}}]}}}}"#
    )
    .unwrap();
    let text = last_assistant_text(&path).unwrap();
    assert!(classify_has_question(&text));
}

#[test]
fn stop_variant_accepts_has_question() {
    let ev = EventKind::Stop {
        session_id: "abc".to_string(),
        has_question: Some(true),
    };
    match ev {
        EventKind::Stop { has_question, .. } => assert_eq!(has_question, Some(true)),
        _ => panic!(),
    }
}

#[test]
fn stop_payload_without_transcript_path_compiles_and_defaults() {
    let raw = r#"{"session_id":"abc"}"#;
    let v: serde_json::Value = serde_json::from_str(raw).unwrap();
    assert!(v.get("transcript_path").is_none());
}
