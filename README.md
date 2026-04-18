# ccfocus

A macOS menu bar app that tracks multiple Claude Code sessions and lets you jump to the Ghostty pane that triggered a notification.

## Requirements

- macOS Ventura (13.0) or later
- [Claude Code](https://claude.com/claude-code)

## Installation

```bash
brew install --cask negipo/tap/ccfocus
```

This installs `ccfocus` into `/Applications`, symlinks `ccfocus-logger` onto your `PATH`, clears the quarantine attribute, and registers the required hooks in `~/.claude/settings.json`.

To start the menu bar app:

```bash
open /Applications/ccfocus.app
```

## Uninstall

```bash
brew uninstall --cask ccfocus
```

The uninstall preflight removes ccfocus entries from `~/.claude/settings.json`. Use `brew uninstall --zap --cask ccfocus` to also remove logs and preferences.

## Building from source

For development:

```bash
git clone https://github.com/negipo/ccfocus.git
cd ccfocus
make install
```

This builds `ccfocus-logger` (CLI) and `ccfocus` (menu bar app), registers Claude Code hooks, and copies the app to `/Applications`.
