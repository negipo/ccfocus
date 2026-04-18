use crate::git::CommandRunner;
use anyhow::Result;
use std::collections::HashSet;
use std::thread::sleep;
use std::time::Duration;

const GHOSTTY_DUMP_SCRIPT: &str = r#"
tell application "Ghostty"
    set out to ""
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                try
                    set n to name of term
                on error
                    set n to ""
                end try
                try
                    set wd to working directory of term
                on error
                    set wd to ""
                end try
                try
                    set tid to id of term
                on error
                    set tid to ""
                end try
                set out to out & "id=" & tid & " | name=" & n & " | wd=" & wd & linefeed
            end repeat
        end repeat
    end repeat
    return out
end tell
"#;

#[derive(Debug, Clone, PartialEq)]
pub struct Term {
    pub id: String,
    pub name: String,
    pub wd: String,
}

#[derive(Debug, PartialEq)]
pub enum MatchResult {
    Unique(String),
    None,
    Multiple,
}

pub fn parse_ghostty_dump(s: &str) -> Vec<Term> {
    s.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| {
            let mut id = None;
            let mut name = None;
            let mut wd = None;
            for part in l.split(" | ") {
                if let Some(v) = part.strip_prefix("id=") {
                    id = Some(v.to_string());
                } else if let Some(v) = part.strip_prefix("name=") {
                    name = Some(v.to_string());
                } else if let Some(v) = part.strip_prefix("wd=") {
                    wd = Some(v.to_string());
                }
            }
            Some(Term {
                id: id?,
                name: name?,
                wd: wd?,
            })
        })
        .collect()
}

pub fn pick_match(terms: &[Term], cwd: &str) -> MatchResult {
    pick_match_excluding(terms, cwd, &HashSet::new())
}

pub fn pick_match_excluding(
    terms: &[Term],
    cwd: &str,
    claimed: &HashSet<String>,
) -> MatchResult {
    let canonical_cwd = std::fs::canonicalize(cwd)
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| cwd.to_string());
    let cands: Vec<&Term> = terms
        .iter()
        .filter(|t| {
            let canonical_wd = std::fs::canonicalize(&t.wd)
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| t.wd.clone());
            canonical_wd == canonical_cwd
                && t.name.contains("Claude Code")
                && !claimed.contains(&t.id)
        })
        .collect();
    match cands.len() {
        0 => MatchResult::None,
        1 => MatchResult::Unique(cands[0].id.clone()),
        _ => MatchResult::Multiple,
    }
}

pub fn enumerate_terminals(runner: &impl CommandRunner) -> Result<Vec<Term>> {
    let out = runner.run("osascript", &["-e", GHOSTTY_DUMP_SCRIPT])?;
    Ok(parse_ghostty_dump(&out))
}

pub fn find_terminal_id_with_retry(
    runner: &impl CommandRunner,
    cwd: &str,
    claimed: &HashSet<String>,
    max_attempts: usize,
    interval: Duration,
) -> Option<String> {
    for i in 0..max_attempts {
        if i > 0 {
            sleep(interval);
        }
        let Ok(terms) = enumerate_terminals(runner) else {
            continue;
        };
        if let MatchResult::Unique(id) = pick_match_excluding(&terms, cwd, claimed) {
            return Some(id);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_three_terminals() {
        let out = "id=T1 | name=Claude Code | wd=/foo\n\
                   id=T2 | name=zsh | wd=/bar\n\
                   id=T3 | name=Claude Code | wd=/foo\n";
        let terms = parse_ghostty_dump(out);
        assert_eq!(terms.len(), 3);
        assert_eq!(terms[0].id, "T1");
        assert_eq!(terms[0].name, "Claude Code");
        assert_eq!(terms[0].wd, "/foo");
    }

    #[test]
    fn match_unique_by_cwd_and_name() {
        let terms = vec![
            Term {
                id: "T1".into(),
                name: "\u{2802} Claude Code".into(),
                wd: "/foo".into(),
            },
            Term {
                id: "T2".into(),
                name: "zsh".into(),
                wd: "/foo".into(),
            },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }

    #[test]
    fn match_none_when_no_claude_code() {
        let terms = vec![Term {
            id: "T1".into(),
            name: "zsh".into(),
            wd: "/foo".into(),
        }];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::None);
    }

    #[test]
    fn match_multiple_when_same_cwd_two_claude() {
        let terms = vec![
            Term {
                id: "T1".into(),
                name: "\u{2802} Claude Code".into(),
                wd: "/foo".into(),
            },
            Term {
                id: "T2".into(),
                name: "\u{2733} Claude Code".into(),
                wd: "/foo".into(),
            },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Multiple);
    }

    #[test]
    fn match_handles_spinner_prefix() {
        let terms = vec![Term {
            id: "T1".into(),
            name: "\u{2810} Claude Code".into(),
            wd: "/foo".into(),
        }];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }

    #[test]
    fn excluding_claimed_resolves_to_remaining() {
        let terms = vec![
            Term {
                id: "T1".into(),
                name: "Claude Code".into(),
                wd: "/foo".into(),
            },
            Term {
                id: "T2".into(),
                name: "Claude Code".into(),
                wd: "/foo".into(),
            },
        ];
        let claimed = HashSet::from(["T1".to_string()]);
        let m = pick_match_excluding(&terms, "/foo", &claimed);
        assert_eq!(m, MatchResult::Unique("T2".into()));
    }

    #[test]
    fn excluding_claimed_when_all_claimed_returns_none() {
        let terms = vec![
            Term {
                id: "T1".into(),
                name: "Claude Code".into(),
                wd: "/foo".into(),
            },
            Term {
                id: "T2".into(),
                name: "Claude Code".into(),
                wd: "/foo".into(),
            },
        ];
        let claimed = HashSet::from(["T1".to_string(), "T2".to_string()]);
        let m = pick_match_excluding(&terms, "/foo", &claimed);
        assert_eq!(m, MatchResult::None);
    }

    #[test]
    fn excluding_claimed_not_in_terms_is_noop() {
        let terms = vec![Term {
            id: "T1".into(),
            name: "Claude Code".into(),
            wd: "/foo".into(),
        }];
        let claimed = HashSet::from(["T_OTHER".to_string()]);
        let m = pick_match_excluding(&terms, "/foo", &claimed);
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }

    #[test]
    fn excluding_empty_claimed_single_pane_matches() {
        let terms = vec![Term {
            id: "T1".into(),
            name: "Claude Code".into(),
            wd: "/foo".into(),
        }];
        let m = pick_match_excluding(&terms, "/foo", &HashSet::new());
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }
}
