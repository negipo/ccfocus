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

## Session states

Each tracked session appears in the menu bar with a colored dot and an optional label indicating its current state.

States are listed from most to least urgent for the user to act on.

| State          | Color       | Label       | Meaning                                                                     |
|----------------|-------------|-------------|-----------------------------------------------------------------------------|
| `asking`       | orange      | last text / `asking` | Claude ended its turn with a question — respond immediately        |
| `waitingInput` | orange      | notification message | Claude Code emitted a Notification (permission prompt, or idle timeout) |
| `running`      | green       | —           | Claude is working (prompt submitted, tool calls in flight)                  |
| `idle`         | gray        | `idle`      | Session has started; waiting for the first user prompt                      |
| `done`         | gray        | `done`      | Claude ended its turn without a question                                    |
| `stale`        | dim gray    | —           | Session has not produced any event for 30+ minutes                          |
| `deceased`     | faded gray  | —           | Claude process exited or Ghostty pane closed; collapsed at the bottom       |

### Transitions

- `session_start` puts a session into `idle`.
- `user_prompt_submit` and `pre_tool_use` move it to `running`.
- `stop` with a detected question-like ending goes to `asking`; otherwise `done`.
- `notification` moves a session to `waitingInput`. Claude Code fires a Notification whenever it shows a permission prompt OR sits idle for about one minute, so a forgotten `done` session escalates to `waitingInput` roughly 60 seconds after the last event, regardless of whether asking-detection fired.
- Any active state (`idle` / `running` / `asking` / `waitingInput` / `done`) becomes `stale` after 30 minutes without new events.
- A `stale` session with no tracked Claude process is marked `deceased` after 2.5 hours.
- `deceased` is terminal.

The popover auto-opens when a session transitions into `asking`, `waitingInput`, or `done` so you can react without polling the menu bar.

### How `asking` is detected

At `stop` hook time the logger reads the tail of the session's transcript jsonl, extracts the most recent assistant text, and checks whether the last three non-empty lines contain a half- or full-width question mark or a polite-request pattern (`確認してください`, `試していただけ`, etc.). If the heuristic can't read the transcript, the session falls back to `done` and will still be caught by the 60-second idle `waitingInput` escalation.

## Building from source

For development:

```bash
git clone https://github.com/negipo/ccfocus.git
cd ccfocus
make install
```

This builds `ccfocus-logger` (CLI) and `ccfocus` (menu bar app), registers Claude Code hooks, and copies the app to `/Applications`.
