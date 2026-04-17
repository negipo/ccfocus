use anyhow::{Context, Result};
use serde_json::{Map, Value};
use std::fs;
use std::path::PathBuf;

fn settings_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".claude").join("settings.json")
}

fn hooks_fragment() -> Value {
    serde_json::json!({
        "hooks": {
            "SessionStart":     [{"hooks": [{"type": "command", "command": "ccsplit-logger session-start"}]}],
            "Notification":     [{"hooks": [{"type": "command", "command": "ccsplit-logger notification"}]}],
            "Stop":             [{"hooks": [{"type": "command", "command": "ccsplit-logger stop"}]}],
            "PreToolUse":       [{"hooks": [{"type": "command", "command": "ccsplit-logger pre-tool-use"}]}],
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "ccsplit-logger user-prompt-submit"}]}]
        }
    })
}

fn merge_objects(base: &mut Map<String, Value>, patch: &Map<String, Value>) {
    for (key, patch_val) in patch {
        match (base.get_mut(key), patch_val) {
            (Some(Value::Object(base_inner)), Value::Object(patch_inner)) => {
                merge_objects(base_inner, patch_inner);
            }
            (Some(Value::Array(base_arr)), Value::Array(patch_arr)) => {
                for item in patch_arr {
                    if !base_arr.contains(item) {
                        base_arr.push(item.clone());
                    }
                }
            }
            _ => {
                base.insert(key.clone(), patch_val.clone());
            }
        }
    }
}

pub fn run() -> Result<()> {
    run_with_path(&settings_path())
}

pub fn run_with_path(path: &PathBuf) -> Result<()> {
    let mut settings: Value = if path.exists() {
        let content = fs::read_to_string(path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        serde_json::from_str(&content)
            .with_context(|| format!("failed to parse {}", path.display()))?
    } else {
        Value::Object(Map::new())
    };

    let fragment = hooks_fragment();
    if let (Some(base_obj), Some(patch_obj)) = (settings.as_object_mut(), fragment.as_object()) {
        merge_objects(base_obj, patch_obj);
    }

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let out = serde_json::to_string_pretty(&settings)?;
    fs::write(path, out.as_bytes())
        .with_context(|| format!("failed to write {}", path.display()))?;

    eprintln!("hooks merged into {}", path.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn installs_into_empty_file() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        run_with_path(&path).unwrap();

        let content: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        let hooks = content.get("hooks").unwrap().as_object().unwrap();
        assert_eq!(hooks.len(), 5);
        assert!(hooks.contains_key("SessionStart"));
        assert!(hooks.contains_key("Stop"));
    }

    #[test]
    fn merges_without_overwriting_existing_keys() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        fs::write(&path, r#"{"model": "opus", "hooks": {"MyHook": []}}"#).unwrap();

        run_with_path(&path).unwrap();

        let content: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(content.get("model").unwrap(), "opus");
        let hooks = content.get("hooks").unwrap().as_object().unwrap();
        assert!(hooks.contains_key("MyHook"));
        assert!(hooks.contains_key("SessionStart"));
    }

    #[test]
    fn idempotent_on_repeated_runs() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        run_with_path(&path).unwrap();
        let first = fs::read_to_string(&path).unwrap();

        run_with_path(&path).unwrap();
        let second = fs::read_to_string(&path).unwrap();

        assert_eq!(first, second);
    }
}
