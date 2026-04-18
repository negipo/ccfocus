use once_cell::sync::Lazy;
use regex::Regex;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

const TAIL_READ_LIMIT: u64 = 256 * 1024;

static ASK_QMARK: Lazy<Regex> = Lazy::new(|| Regex::new(r"[?？]").unwrap());
static ASK_POLITE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)(確認してください|試していただけ|確認していただけ|教えていただけ|教えてください|let me know|please confirm|please advise)")
        .unwrap()
});

pub fn last_assistant_text(path: &Path) -> Option<String> {
    let size = std::fs::metadata(path).ok()?.len();
    let read_bytes = size.min(TAIL_READ_LIMIT);
    let mut f = File::open(path).ok()?;
    if size > read_bytes {
        f.seek(SeekFrom::End(-(read_bytes as i64))).ok()?;
    }
    let mut buf = Vec::with_capacity(read_bytes as usize);
    f.read_to_end(&mut buf).ok()?;
    let start = if size > read_bytes {
        buf.iter().position(|&b| b == b'\n').map(|i| i + 1).unwrap_or(0)
    } else {
        0
    };
    let text = std::str::from_utf8(&buf[start..]).ok()?;
    for line in text.lines().rev() {
        let v: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if v.get("type").and_then(|t| t.as_str()) != Some("assistant") {
            continue;
        }
        let content = v
            .get("message")
            .and_then(|m| m.get("content"))
            .and_then(|c| c.as_array());
        let Some(content) = content else { continue };
        let joined: Vec<&str> = content
            .iter()
            .filter(|c| c.get("type").and_then(|t| t.as_str()) == Some("text"))
            .filter_map(|c| c.get("text").and_then(|t| t.as_str()))
            .collect();
        if joined.is_empty() {
            continue;
        }
        return Some(joined.join("\n"));
    }
    None
}

pub fn classify_has_question(text: &str) -> bool {
    let tail: String = text
        .lines()
        .map(|l| l.trim_end())
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .take(3)
        .collect::<Vec<_>>()
        .join("\n");
    ASK_QMARK.is_match(&tail) || ASK_POLITE.is_match(&tail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qmark_in_last_line_is_question() {
        assert!(classify_has_question("結果です。\nこれで進めていいですか?"));
    }

    #[test]
    fn fullwidth_qmark_is_question() {
        assert!(classify_has_question("どちらにしましょうか？"));
    }

    #[test]
    fn polite_request_is_question() {
        assert!(classify_has_question("ビルドしました。\n動作を確認してください"));
    }

    #[test]
    fn plain_done_report_is_not_question() {
        assert!(!classify_has_question("実装完了しました。\nテストも通っています。"));
    }

    #[test]
    fn dou_iu_is_not_question_without_qmark() {
        assert!(!classify_has_question("どういう設計になっているか整理しました。"));
    }

    #[test]
    fn qmark_outside_tail3_is_ignored() {
        let text = "?\n\n\n(1) 最初に\n(2) 次に\n(3) 最後に完了しました。";
        assert!(!classify_has_question(text));
    }

    #[test]
    fn empty_text_is_not_question() {
        assert!(!classify_has_question(""));
    }

    #[test]
    fn english_let_me_know_is_question() {
        assert!(classify_has_question("Built and tested.\nLet me know if you'd like any changes."));
    }

    #[test]
    fn english_please_confirm_is_question() {
        assert!(classify_has_question("Ready to proceed. Please confirm."));
    }

    #[test]
    fn english_please_advise_case_insensitive_is_question() {
        assert!(classify_has_question("Two options remain. please advise"));
    }

    #[test]
    fn english_plain_done_is_not_question() {
        assert!(!classify_has_question("Implementation complete.\nAll tests pass."));
    }

    use std::io::Write;

    fn write_jsonl(path: &std::path::Path, lines: &[&str]) {
        let mut f = std::fs::File::create(path).unwrap();
        for line in lines {
            writeln!(f, "{}", line).unwrap();
        }
    }

    #[test]
    fn last_assistant_text_returns_latest_text_block() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.jsonl");
        write_jsonl(&path, &[
            r#"{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}"#,
            r#"{"type":"assistant","message":{"content":[{"type":"text","text":"first"}]}}"#,
            r#"{"type":"user","message":{"content":[{"type":"text","text":"again"}]}}"#,
            r#"{"type":"assistant","message":{"content":[{"type":"text","text":"second turn\nend?"}]}}"#,
        ]);
        let out = last_assistant_text(&path).unwrap();
        assert!(out.contains("second turn"));
        assert!(out.contains("end?"));
    }

    #[test]
    fn last_assistant_text_joins_multiple_text_blocks() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.jsonl");
        write_jsonl(&path, &[
            r#"{"type":"assistant","message":{"content":[{"type":"text","text":"part1"},{"type":"tool_use","id":"x","name":"R","input":{}},{"type":"text","text":"part2?"}]}}"#,
        ]);
        let out = last_assistant_text(&path).unwrap();
        assert!(out.contains("part1"));
        assert!(out.contains("part2?"));
    }

    #[test]
    fn last_assistant_text_missing_file_returns_none() {
        assert!(last_assistant_text(std::path::Path::new("/no/such/file.jsonl")).is_none());
    }

    #[test]
    fn last_assistant_text_only_tool_use_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.jsonl");
        write_jsonl(&path, &[
            r#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x","name":"R","input":{}}]}}"#,
        ]);
        assert!(last_assistant_text(&path).is_none());
    }
}
