use anyhow::{Context, Result};
use serde_json::Value;
use std::fs;
use std::path::PathBuf;

fn settings_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".claude").join("settings.json")
}

pub fn run() -> Result<()> {
    run_with_path(&settings_path())
}

const HOOK_EVENTS: &[&str] = &[
    "SessionStart",
    "Notification",
    "Stop",
    "PreToolUse",
    "UserPromptSubmit",
];

pub fn run_with_path(path: &PathBuf) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }

    let content = fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let mut settings: Value = serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;

    let Some(root) = settings.as_object_mut() else {
        return Ok(());
    };
    let Some(Value::Object(hooks)) = root.get_mut("hooks") else {
        return Ok(());
    };

    for event in HOOK_EVENTS {
        let Some(Value::Array(entries)) = hooks.get_mut(*event) else {
            continue;
        };
        entries.retain_mut(|entry| {
            let Some(entry_obj) = entry.as_object_mut() else {
                return true;
            };
            let Some(Value::Array(cmds)) = entry_obj.get_mut("hooks") else {
                return true;
            };
            cmds.retain(|cmd| {
                cmd.get("command")
                    .and_then(Value::as_str)
                    .map(|s| !s.starts_with("ccfocus-logger "))
                    .unwrap_or(true)
            });
            !cmds.is_empty()
        });
    }

    for event in HOOK_EVENTS {
        if matches!(hooks.get(*event), Some(Value::Array(a)) if a.is_empty()) {
            hooks.remove(*event);
        }
    }

    if hooks.is_empty() {
        root.remove("hooks");
    }

    let out = serde_json::to_string_pretty(&settings)?;
    fs::write(path, out.as_bytes())
        .with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn noop_when_settings_missing() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        run_with_path(&path).unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn install_then_uninstall_restores_empty() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        crate::commands::install::run_with_path(&path).unwrap();
        run_with_path(&path).unwrap();

        let content = fs::read_to_string(&path).unwrap();
        let parsed: Value = serde_json::from_str(&content).unwrap();
        assert!(parsed.get("hooks").is_none(), "hooks should be removed entirely");
    }

    #[test]
    fn preserves_other_hooks_and_top_level_keys() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        let initial = r#"{
            "model": "opus",
            "hooks": {
                "SessionStart": [{"hooks": [{"type": "command", "command": "my-tool run"}]}],
                "MyHook": [{"hooks": [{"type": "command", "command": "something"}]}]
            }
        }"#;
        fs::write(&path, initial).unwrap();
        crate::commands::install::run_with_path(&path).unwrap();
        run_with_path(&path).unwrap();

        let parsed: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(parsed.get("model").unwrap(), "opus");
        let hooks = parsed.get("hooks").unwrap().as_object().unwrap();
        assert!(hooks.contains_key("MyHook"));
        let session_start = hooks.get("SessionStart").unwrap().as_array().unwrap();
        assert_eq!(session_start.len(), 1);
        let cmds = session_start[0].get("hooks").unwrap().as_array().unwrap();
        assert_eq!(cmds.len(), 1);
        assert_eq!(
            cmds[0].get("command").unwrap().as_str().unwrap(),
            "my-tool run"
        );
    }

    #[test]
    fn idempotent_on_repeated_uninstall() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        crate::commands::install::run_with_path(&path).unwrap();
        run_with_path(&path).unwrap();
        let first = fs::read_to_string(&path).unwrap();
        run_with_path(&path).unwrap();
        let second = fs::read_to_string(&path).unwrap();
        assert_eq!(first, second);
    }
}
