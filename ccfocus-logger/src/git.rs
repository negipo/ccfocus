use anyhow::Result;

pub trait CommandRunner {
    fn run(&self, prog: &str, args: &[&str]) -> Result<String>;
}

pub struct RealRunner;

impl CommandRunner for RealRunner {
    fn run(&self, prog: &str, args: &[&str]) -> Result<String> {
        let out = std::process::Command::new(prog).args(args).output()?;
        if !out.status.success() {
            anyhow::bail!(
                "{} {:?} failed: {}",
                prog,
                args,
                String::from_utf8_lossy(&out.stderr)
            );
        }
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    }
}

pub fn git_branch(runner: &impl CommandRunner, cwd: &str) -> Result<Option<String>> {
    match runner.run("git", &["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]) {
        Ok(s) => {
            let trimmed = s.trim().to_string();
            if trimmed.is_empty() || trimmed == "HEAD" {
                Ok(None)
            } else {
                Ok(Some(trimmed))
            }
        }
        Err(_) => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeRunner(std::result::Result<String, String>);

    impl CommandRunner for FakeRunner {
        fn run(&self, _prog: &str, _args: &[&str]) -> Result<String> {
            self.0
                .as_ref()
                .map(|s| s.clone())
                .map_err(|e| anyhow::anyhow!("{}", e))
        }
    }

    #[test]
    fn returns_branch_on_success() {
        let runner = FakeRunner(Ok("feature/x\n".to_string()));
        let b = git_branch(&runner, "/tmp").unwrap();
        assert_eq!(b, Some("feature/x".to_string()));
    }

    #[test]
    fn returns_none_on_failure() {
        let runner = FakeRunner(Err("fatal: not a git repo".to_string()));
        let b = git_branch(&runner, "/tmp").unwrap();
        assert_eq!(b, None);
    }

    #[test]
    fn returns_none_on_detached_head() {
        let runner = FakeRunner(Ok("HEAD\n".to_string()));
        let b = git_branch(&runner, "/tmp").unwrap();
        assert_eq!(b, None);
    }
}
