# ccsplit

A macOS menu bar app that tracks multiple Claude Code sessions and lets you jump to the Ghostty pane that triggered a notification.

## Requirements

- Rust toolchain
- Xcode Command Line Tools
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

## Installation

```bash
git clone https://github.com/negipo/ccsplit.git
cd ccsplit
make install
```

This builds ccsplit-logger (CLI) and ccsplit-app (menu bar app), registers Claude Code hooks, and copies the app to /Applications. The app registers itself as a login item on first launch.

To install only ccsplit-logger (without the menu bar app) from the remote:

```bash
cargo install --git https://github.com/negipo/ccsplit ccsplit-logger
ccsplit-logger install  # register Claude Code hooks
```
