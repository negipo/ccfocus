use ccfocus_logger::event::{Event, EventKind};

#[test]
fn session_start_serializes_to_expected_json() {
    let ev = Event {
        ts: "2026-04-16T09:12:34.567Z".to_string(),
        kind: EventKind::SessionStart {
            session_id: "abc".to_string(),
            terminal_id: Some("B9BE".to_string()),
            cwd: "/tmp".to_string(),
            git_branch: Some("main".to_string()),
            claude_pid: Some(12345),
            claude_start_time: Some("Wed Apr 16 09:12:34 2026".to_string()),
            claude_comm: Some("claude".to_string()),
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"event\":\"session_start\""));
    assert!(json.contains("\"session_id\":\"abc\""));
    assert!(json.contains("\"terminal_id\":\"B9BE\""));
    assert!(json.contains("\"claude_pid\":12345"));
}

#[test]
fn notification_serializes_without_extra_fields() {
    let ev = Event {
        ts: "2026-04-16T09:13:45.890Z".to_string(),
        kind: EventKind::Notification {
            session_id: "abc".to_string(),
            message: "approval needed".to_string(),
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"event\":\"notification\""));
    assert!(!json.contains("\"terminal_id\""));
}

#[test]
fn terminal_id_null_is_serialized_as_null_not_missing() {
    let ev = Event {
        ts: "2026-04-16T09:12:34.567Z".to_string(),
        kind: EventKind::SessionStart {
            session_id: "abc".to_string(),
            terminal_id: None,
            cwd: "/tmp".to_string(),
            git_branch: None,
            claude_pid: None,
            claude_start_time: None,
            claude_comm: None,
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"terminal_id\":null"));
    assert!(json.contains("\"git_branch\":null"));
    assert!(json.contains("\"claude_pid\":null"));
}

#[test]
fn stop_serializes_has_question_when_true() {
    let ev = Event {
        ts: "2026-04-18T00:00:00.000Z".to_string(),
        kind: EventKind::Stop {
            session_id: "abc".to_string(),
            has_question: Some(true),
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"event\":\"stop\""));
    assert!(json.contains("\"has_question\":true"));
}

#[test]
fn stop_omits_has_question_when_none() {
    let ev = Event {
        ts: "2026-04-18T00:00:00.000Z".to_string(),
        kind: EventKind::Stop {
            session_id: "abc".to_string(),
            has_question: None,
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(!json.contains("has_question"));
}

#[test]
fn stop_deserializes_legacy_event_without_has_question() {
    let raw = r#"{"ts":"2026-04-18T00:00:00.000Z","event":"stop","session_id":"abc"}"#;
    let ev: Event = serde_json::from_str(raw).unwrap();
    match ev.kind {
        EventKind::Stop { has_question, .. } => assert!(has_question.is_none()),
        _ => panic!("wrong variant"),
    }
}
