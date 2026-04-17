# ccfocus

A macOS menu bar app that tracks multiple Claude Code sessions and lets you jump to the Ghostty pane that triggered a notification.

## Requirements

- Rust toolchain
- Xcode Command Line Tools
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

## Installation

```bash
git clone https://github.com/negipo/ccfocus.git
cd ccfocus
make install
```

This builds ccfocus-logger (CLI) and ccfocus-app (menu bar app), registers Claude Code hooks, and copies the app to /Applications.

## Usage

```bash
open /Applications/ccfocus-app.app
```

The app appears in the menu bar. It registers itself as a login item on first launch, so it will start automatically on reboot.
