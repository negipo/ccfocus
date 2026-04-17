use ccfocus_logger::cli::Cli;
use clap::Parser;

#[test]
fn hook_commands_require_detach() {
    for sub in [
        "session-start",
        "notification",
        "stop",
        "pre-tool-use",
        "user-prompt-submit",
    ] {
        let cli = Cli::try_parse_from(["ccfocus-logger", sub]).unwrap();
        assert!(cli.needs_detach(), "{} should detach", sub);
    }
}
