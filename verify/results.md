# ccsplit Runtime Verification Results

## 検証A: SessionStart $PPID

- 実施日時: 2026-04-16T18:17:36
- $PPID comm: claude
- $PPID command: claude -p say hello and exit --output-format text
- 親方向1段: -/opt/homebrew/bin/zsh (PID 61746)
- 親方向2段: /usr/bin/login (PID 61743)
- 親方向3段: /Applications/Ghostty.app/Contents/MacOS/ghostty (PID 61692)
- GHOSTTY_SURFACE_ID: (空)
- TERM_PROGRAM: ghostty

### 判定

- [x] $PPID が直接 claude 本体を指す → 設計通り

### 採用方針

設計通り `ps -p $PPID` で `comm=claude` が直接取れる。親方向遡りは不要だが、将来のClaude Code内部実装変更に備えて `find_claude_proc` の `max_depth=5` は維持。

CLAUDE_PATTERNS 初期値: `["claude", "claude-code"]` で十分。node/bun wrap されていない。

GHOSTTY_SURFACE_ID は hook env に伝播しないため、upstream PR (terminal.surface_id property) が入るまではcwd+name matchingが唯一の手段。

### 補足

テストは `claude -p` (非インタラクティブ) で実施。インタラクティブ `claude` でも $PPID → claude の関係は同一と推定 (同じバイナリが起動するため)。

## 検証B: SessionStart発火時のGhostty terminal name

- 実施日時: 2026-04-16T18:20:30
- 対象ペイン (claude -p, cwd=ccsplit):
  - 即時: name=claude -p "hello" --output-format text; exit
  - 100ms後: 同上
  - 500ms後: 同上
  - 1500ms後: 同上
- 別ペイン (インタラクティブ claude, cwd=ccsplit):
  - 即時: name=⠐ Claude Code
  - 100ms後: name=⠂ Claude Code
  - 500ms後: name=⠐ Claude Code
  - 1500ms後: name=⠐ Claude Code

### 判定

- [x] インタラクティブ claude では SessionStart 発火時点で name に "Claude Code" が含まれる (スピナー付き)
- claude -p (非インタラクティブ) では title 書き換えが行われない → ccsplit の追跡対象外 (許容)

### 採用方針

name matching は `name.contains("Claude Code")` を使用 (完全一致ではなくsubstring match)。スピナー文字 (⠐ / ⠂ / ✳ 等) がprefixとして付くため。

リトライ設計は 5回 x 100ms で十分。SessionStart発火時点で既にtitle設定済みが確認できたため、ほとんどの場合1回目で確定する見込み。

## 検証C: Ghostty pane focus

- 実施日時: 2026-04-16T18:25 頃
- osascript CLI での focus: ok (iteration方式で成功)
- NSAppleScript (Swift) での focus: ok
- 別tab時の挙動: ok (別tabのterminalにもfocusが飛ぶ)
- 権限ダイアログ: 出なかった (既にAutomation権限許可済みと推定)

### SDEF確認結果

Ghostty SDEF の `focus` コマンド:
- direct parameter として terminal specifier を取る
- 構文: `focus term` (termはterminalオブジェクト参照)
- `focus on term` は構文エラー (`on` がhandler定義と解釈される)
- `select term` も非対応 (terminalは select メッセージを認識しない)

正しい構文:
```applescript
tell application "Ghostty"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                if (id of term) is targetId then
                    focus term
                end if
            end repeat
        end repeat
    end repeat
end tell
```

window前面化は `focus` コマンド自体が行う ("Focus a terminal, bringing its window to the front" とSDEFに記述)。`activate` は別途不要。

### 判定

- [x] iteration方式で正しくfocusが飛ぶ
- [x] NSAppleScript経由でも同一の挙動

### 採用方針

GhosttyFocus実装では全terminal走査 + id一致でfocusを行う。`first terminal whose id is X` 構文はエラーになるため使わない。
