# ccsplit Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: 複数のClaude CodeセッションをGhostty paneと紐付けて、メニューバーから瞬時にpaneへ誘導するmacOS常駐アプリを、append-onlyイベントログを真実の源として実装する。

Architecture: Claude Code Hookから呼ばれるRust製CLI `ccsplit-logger` がAppleScriptでGhostty paneを特定してjsonlに書き込み、SwiftUIの `ccsplit.app` がFSEventsでログを追尾して状態を復元・UI表示・AppleScript focusを行う。状態の真実の源はファイル、appはその投影層。

Tech Stack:
- ccsplit-logger: Rust (edition 2021)、serde_json、clap、std::process::Command (AppleScript / ps / git実行)
- ccsplit.app: Swift 5.9+、SwiftUI、MenuBarExtra (macOS 13+)、CoreServices (FSEvents) + 追記ポーリング二段構え、NSAppleScript、macOS .app bundle (LSUIElement)
- プロジェクト構成: Cargo workspace (Rust CLI) + Xcode project (macOSアプリ、.app bundle生成) の monorepo
- 参照: docs/ccsplit-design.md (全設計と不変条件)

Verification Results (Phase 0):
- 検証A: $PPID → claude 直接 (comm=claude)。設計通り
- 検証B: インタラクティブ claude では SessionStart 発火時点で name に "Claude Code" を含む (スピナーprefix付き)。matching は contains を使用
- 検証C: `focus term` (iteration方式) で別tab/別windowのpaneにfocus可能。`focus on` 構文はエラー
- GHOSTTY_SURFACE_ID は hook env に伝播しない
- 詳細: verify/results.md

---

## ファイル構造

MVP完成時点で存在するファイル:

```
ccsplit/
├── Cargo.toml                                  # Rust workspace
├── ccsplit-logger/
│   ├── Cargo.toml                              # Logger CLIのパッケージ定義
│   └── src/
│       ├── main.rs                             # clap dispatch
│       ├── cli.rs                              # サブコマンド定義
│       ├── event.rs                            # Eventスキーマ (serde)
│       ├── log_writer.rs                       # jsonl append (O_APPEND原子書き込み)
│       ├── log_path.rs                         # ~/Library/Application Support/ccsplit/events/YYYY-MM-DD.jsonl 解決
│       ├── ghostty.rs                          # AppleScriptでterminal列挙、cwd+name一致で絞り込み
│       ├── git.rs                              # git branch取得
│       ├── claude_proc.rs                      # ps -p $PPID -o pid=,lstart=,comm=
│       └── commands/
│           ├── session_start.rs
│           ├── notification.rs
│           ├── stop.rs
│           ├── pre_tool_use.rs
│           └── user_prompt_submit.rs
│   └── tests/
│       ├── event_serde.rs
│       ├── log_writer.rs
│       └── log_path.rs
├── ccsplit-app/
│   ├── ccsplit-app.xcodeproj/                  # Xcodeプロジェクト (.app ターゲット)
│   ├── ccsplit-app/
│   │   ├── Info.plist                          # LSUIElement=true、bundle identifier 等
│   │   ├── ccsplit_app.entitlements            # App sandbox無効 (AppleScript使用のため)
│   │   ├── ccsplitApp.swift                    # @main entry (MenuBarExtra)
│   │   ├── AppState.swift                      # ObservableObject (registry + manualPairings)
│   │   ├── Event.swift                         # logger側と対応するCodable定義
│   │   ├── EventLogPath.swift                  # ログディレクトリ/ファイル解決
│   │   ├── EventLogReader.swift                # 全jsonl古い順走査 + 1行ずつparse
│   │   ├── LogTail.swift                       # FSEvents通知 + 1s保険ポーリング + 既読offset管理
│   │   ├── SessionRegistry.swift               # イベントをapplyするprojection
│   │   ├── SessionStatus.swift                 # 状態遷移マシン
│   │   ├── GhosttyFocus.swift                  # NSAppleScript `tell app "Ghostty" to focus terminal id ...`
│   │   ├── MenuBarView.swift                   # 吹き出しUI
│   │   ├── ManualPairView.swift                # 未紐付けセッションの手動選択UI
│   │   ├── ManualPairingsStore.swift           # manual_pairings.json の永続化 (sid -> terminal_id)
│   │   └── LivenessChecker.swift               # 10秒周期 PID3点 + terminal存在確認
│   └── ccsplit-appTests/
│       ├── EventLogReaderTests.swift
│       ├── SessionRegistryTests.swift
│       ├── SessionStatusTests.swift
│       ├── LogTailTests.swift
│       ├── ManualPairingsStoreTests.swift
│       └── LivenessCheckerTests.swift
├── tmp/
│   └── doc/                                    # 設計ドキュメントと検証結果
└── LICENSE
```

設計原則:
- logger側はステートレス。入力=Hook payload + 環境、出力=jsonl1行
- app側の `SessionRegistry` は純粋関数的にイベント列をapply。テストはイベント列in/Registry out
- `GhosttyFocus` と `LogTail.Watcher` はI/O境界として分離、ロジックテストには現れない
- logger側の `ghostty.rs` はAppleScript実行を関数境界で分離し、テストでは固定のAppleScript出力をparseするテストに留める

---

## フェーズ0: 実機検証

実装の前提3件を実機で検証する:
- 検証A: SessionStart hook内の `$PPID` がClaude Code本体を指すか
- 検証B: SessionStart hook発火時点でGhostty terminal name が `Claude Code` になっているか
- 検証C: `tell application "Ghostty" to focus terminal id <id>` 相当のAppleScriptでpaneに飛べるか (AppleScript権限とGhostty SDEFの挙動も含む)

Ghostty focusは本アプリのコア価値そのもの (通知→paneへ飛ぶ) なので、最初に成立確認する。成立しない場合の代替案 (Accessibility API経由、Ghostty upstream surface_id PR頼み) の判断材料とする。

### Task 0.1: 検証用ディレクトリ準備

Files:
- Create: `verify/verify_hook.sh`
- Create: `verify/verify_ghostty.applescript`
- Create: `verify/results.md`

- [x] Step 1: `verify/` ディレクトリを作成

Run: `mkdir -p tmp/verify`
Expected: エラーなし

- [x] Step 2: `verify/verify_hook.sh` を作成

```bash
#!/bin/bash
# SessionStart Hookから呼ばれ、親プロセス情報と環境を記録する検証スクリプト
# hook payload は stdin に JSON で渡される
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT_DIR="$HOME/.ccsplit-verify"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/hook_$STAMP.txt"

PAYLOAD=$(\cat)

{
  echo "=== SessionStart Hook Verify $STAMP ==="
  echo "--- payload ---"
  echo "$PAYLOAD"
  echo "--- env.PPID=$PPID ---"
  echo "--- ps -p \$PPID ---"
  ps -p "$PPID" -o pid=,ppid=,lstart=,comm=,command= 2>&1 || echo "ps failed"
  echo "--- ps 親方向3段 ---"
  PID=$PPID
  for i in 1 2 3; do
    PARENT=$(ps -p "$PID" -o ppid= 2>/dev/null | tr -d ' ')
    [ -z "$PARENT" ] && break
    ps -p "$PARENT" -o pid=,ppid=,lstart=,comm=,command= 2>&1 || echo "stop"
    PID=$PARENT
  done
  echo "--- env.GHOSTTY_SURFACE_ID=$GHOSTTY_SURFACE_ID ---"
  echo "--- env.TERM_PROGRAM=$TERM_PROGRAM ---"
  echo "--- osascript Ghostty terminal dump ---"
  osascript "$(dirname "$0")/verify_ghostty.applescript" 2>&1 || echo "osascript failed"
} > "$OUT"

# Hookをブロックしない
exit 0
```

Run: `chmod +x verify/verify_hook.sh`
Expected: 作成成功

- [x] Step 3: `verify/verify_ghostty.applescript` を作成

```applescript
tell application "Ghostty"
    set out to ""
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                try
                    set n to name of term
                on error
                    set n to "(no name)"
                end try
                try
                    set wd to working directory of term
                on error
                    set wd to "(no wd)"
                end try
                try
                    set tid to id of term
                on error
                    set tid to "(no id)"
                end try
                set out to out & "id=" & tid & " | name=" & n & " | wd=" & wd & linefeed
            end repeat
        end repeat
    end repeat
    return out
end tell
```

Expected: ファイル作成成功

- [x] Step 4: スクリプトの構文確認

Run: `osascript -c 'return 1' && echo "osascript ok"`
Expected: `osascript ok`

Run: `bash -n verify/verify_hook.sh && echo "bash syntax ok"`
Expected: `bash syntax ok`

- [x] Step 5: 検証足場コミット

```bash
git add verify/verify_hook.sh verify/verify_ghostty.applescript
git commit
```

コミットは `git-committing` スキルに従って作成する。メッセージ例: `chore: add ccsplit runtime verification scripts`

### Task 0.2: 検証A - SessionStart Hookの $PPID と親プロセス系列

Files:
- Modify: `~/.claude/settings.json` (一時追加 → 検証後削除)
- Output: `~/.ccsplit-verify/hook_*.txt`

- [x] Step 1: 検証用のhook設定を `~/.claude/settings.json` に一時追加

追加内容 (SessionStart array の先頭に):
```json
{"hooks": [{"type": "command", "command": "/Users/negipo/src/github.com/negipo/ccsplit/verify/verify_hook.sh"}]}
```

既存のSessionStart hookがある場合は末尾に追加する。ユーザに対し `update-config` スキル相当の編集を行う前に、現在のsettings.jsonの内容を提示して確認する。

- [x] Step 2: Ghosttyで新しいpaneを開き、そのpane内で `cd /Users/negipo/src/github.com/negipo/ccsplit && claude` を実行

Expected: Claude Codeが起動し、`~/.ccsplit-verify/hook_<timestamp>.txt` が生成される

- [x] Step 3: 生成されたtxtを確認

Run: `ls -t ~/.ccsplit-verify/ | head -1` → `hook_<timestamp>.txt`
Run: Read tool で `~/.ccsplit-verify/hook_<timestamp>.txt` を読む

確認項目:
- `ps -p $PPID` の `comm=` が `claude` あるいはそれに相当する (node/bun/claude-code等、どれか)
- 親方向遡りで `claude` を含む行があるか (もし $PPID 直接が違う場合の候補)
- `GHOSTTY_SURFACE_ID` が空でないか (Ghostty由来env)
- `TERM_PROGRAM` の値 (Ghosttyなら `ghostty` のはず)

- [x] Step 4: 結果を `verify/results.md` にまとめる

記録フォーマット:
```markdown
## 検証A: SessionStart $PPID

- 実施日時: <timestamp>
- $PPID comm: <value>
- $PPID command: <value>
- 親方向2段: <value>
- 親方向3段: <value>
- GHOSTTY_SURFACE_ID: <value>
- TERM_PROGRAM: <value>

### 判定
- [ ] $PPID が直接 claude 本体を指す → 設計通り
- [ ] $PPID が claude を指さないが親方向遡りで発見できる → 代替案A2採用
- [ ] どの方向にも claude が見つからない → 代替案A3 (claude_pid=null) or 設計見直し

### 採用方針
<判定結果と次フェーズでの方針>
```

- [x] Step 5: 検証A用の一時hook設定を `~/.claude/settings.json` から削除

元の状態に戻してから検証Bへ進む。

### Task 0.3: 検証B - SessionStart Hook発火時点でのGhostty terminal name

Files:
- Output: `~/.ccsplit-verify/hook_*.txt` (Task 0.2のoutputを流用)

- [x] Step 1: Task 0.2で取得した hook txtの `--- osascript Ghostty terminal dump ---` セクションを確認

確認項目:
- `claude` を実行したpaneに相当する行の `name=` が `Claude Code` になっているか
- そうでない場合、どの値になっているか (shell prompt, cwd basename等)

- [x] Step 2: 追加検証 - リトライありで観測

`verify/verify_hook.sh` に以下を追加 (Task 0.1のスクリプトを編集):

```bash
echo "--- osascript Ghostty dump (after 100ms) ---"
(sleep 0.1 && osascript "$(dirname "$0")/verify_ghostty.applescript") 2>&1 &
echo "--- osascript Ghostty dump (after 500ms) ---"
(sleep 0.5 && osascript "$(dirname "$0")/verify_ghostty.applescript") 2>&1 &
echo "--- osascript Ghostty dump (after 1500ms) ---"
(sleep 1.5 && osascript "$(dirname "$0")/verify_ghostty.applescript") 2>&1 &
wait
```

これで5タイミング (即時・100ms・500ms・1500ms) で `name` の変化を追跡できる。

- [x] Step 3: 再度 `claude` を起動して観測

期待: 即時時点では `name=Claude Code` でなくても、100ms〜1500msの間に `Claude Code` に変化する様子が観測される

- [x] Step 4: 結果を `verify/results.md` の検証Bセクションに追記

```markdown
## 検証B: SessionStart発火時のGhostty terminal name

- 実施日時: <timestamp>
- 即時 name: <value>
- 100ms後 name: <value>
- 500ms後 name: <value>
- 1500ms後 name: <value>

### 判定
- [ ] 即時もしくは数百ms以内に name="Claude Code" → 設計通り (5回100msリトライで十分)
- [ ] 1500ms以内に安定するが変動あり → リトライ上限を延ばす (10回/各200ms等)
- [ ] 何度観測しても name="Claude Code" にならない → 代替案B3 (cwdのみで特定、複数ヒット時は手動選択UI)

### 採用方針
<判定結果と次フェーズでの方針>
```

- [x] Step 5: 検証用hookを settings.json から完全削除

検証B完了後、検証用 verify_hook.sh と verify_ghostty.applescript はリポジトリに残すが、`~/.ccsplit-verify/` の出力と settings.json の一時hookは片付ける。

- [x] Step 6: 結果をコミット

```bash
git add verify/results.md
git commit
```

コミットは `git-committing` スキル使用。メッセージ例: `docs: record runtime verification results for hook PPID and Ghostty terminal name timing`

### Task 0.4: 検証C - Ghostty pane focus (AppleScript制御)

通知からpaneへ飛ぶ操作が成立するかを最初に確認する。成立しなければ以降のUI価値がまるごと消えるため、ccsplit.app実装前に判断する。

Files:
- Create: `verify/verify_focus.applescript`

- [x] Step 1: `verify/verify_focus.applescript` を作成

```applescript
on run argv
    set targetId to item 1 of argv
    tell application "Ghostty"
        activate
        try
            set theTerm to first terminal of first tab of first window whose id is targetId
            focus theTerm
            return "focused via id-match"
        on error errMsg
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with term in terminals of t
                            if (id of term) is targetId then
                                focus term
                                return "focused via iteration"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "NOT FOUND: " & targetId
            on error errMsg2
                return "ERROR: " & errMsg2
            end try
        end try
    end tell
end run
```

- [x] Step 2: 実験対象となるpaneのIDを事前取得

Run: `osascript verify/verify_ghostty.applescript`
Expected: `id=<TID> | name=... | wd=...` 形式で複数paneが列挙される。テスト対象の `TID` をメモ。

- [x] Step 3: 別のpaneをクリックでアクティブにしてから `verify_focus.applescript` を実行

ccsplit.appが実行するコンテキスト (バックグラウンド) に近づけるため、`caffeinate -s osascript ... &` のようにバックグラウンド実行で試すバリエーションも試す。

Run: `osascript verify/verify_focus.applescript <TID>`
Expected: 「`focused via id-match`」もしくは「`focused via iteration`」を返し、指定したpaneが前面に来る

追加確認:
- Ghostty windowが別SpaceにあるときにSpace移動まで行うか (`activate` で前面化されるか)
- タブが別でも前面化されるか
- 権限ダイアログ (Automation: Claude Code → Ghostty の制御許可) が出るか、出た場合の UX
- `NSAppleScript` 経由 (swift run) と `osascript` CLI経由で挙動差があるか

- [x] Step 4: Swift側で `NSAppleScript` 経由で同じ動作が再現するか試すミニマル Swift スクリプト

`verify/verify_focus_swift.swift`:
```swift
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else { fputs("usage: verify_focus_swift.swift <terminal_id>\n", stderr); exit(2) }
let tid = args[1]
let source = """
tell application \"Ghostty\"
    activate
    try
        set theTerm to first terminal of first tab of first window whose id is \"\(tid)\"
        focus theTerm
        return \"focused\"
    end try
end tell
"""
var err: NSDictionary?
guard let script = NSAppleScript(source: source) else { exit(3) }
let res = script.executeAndReturnError(&err)
if let e = err { print("error: \(e)") } else { print(res.stringValue ?? "ok") }
```

Run: `swift verify/verify_focus_swift.swift <TID>`
Expected: `focused` あるいは ok、指定paneに実際にfocusが飛ぶ

- [x] Step 5: 結果を `verify/results.md` の検証Cセクションに追記

```markdown
## 検証C: Ghostty pane focus

- 実施日時: <timestamp>
- osascript CLI での focus: <ok/ng/詳細>
- NSAppleScript (Swift) での focus: <ok/ng/詳細>
- 別Space時の挙動: <ok/ng/詳細>
- 別tab時の挙動: <ok/ng/詳細>
- 権限ダイアログ: <出た/出ない、出たタイミング>

### 判定
- [ ] id-match構文が通り、別Space/別tabでも正しくfocusが飛ぶ → 設計通り
- [ ] id-match構文が通らない → iteration fallbackを採用 (GhosttyFocus実装で全terminal走査)
- [ ] どちらも通らない / focusが飛ばない → 代替案C2: Ghostty upstream `focus` 追加PRを出す、もしくはAccessibility API経由で Window → Pane を選択
- [ ] `activate` が前面化にならない → `tell application "System Events" to set frontmost of process "Ghostty" to true` を追加

### 採用方針
<判定結果と次フェーズでの方針>
```

- [x] Step 6: 結果をコミット

```bash
git add verify/results.md verify/verify_focus.applescript verify/verify_focus_swift.swift
git commit
```

メッセージ例: `docs: verify Ghostty pane focus via AppleScript`

### フェーズ0の判定ゲート (ユーザ確認)

results.md 3件 (A / B / C) の採用方針をユーザに提示し、以下のいずれかに確定:
1. 全て設計通り → フェーズ1へ
2. 代替案 (A2/A3/B3/C2等) のどれを採用するか確定 → 設計ドキュメントを差分更新してフェーズ1へ
3. 検証Cが総崩れ (focus不能) → コア価値が消えるため、Ghostty upstream PR 待ち か、設計を大きく見直す

設計更新があれば本計画の後続タスクにも反映する。

---

## フェーズ1: プロジェクト足場 (ユーザ確認必須)

新規ファイル `Cargo.toml` (workspace)、`ccsplit-logger/Cargo.toml`、`ccsplit-app/ccsplit-app.xcodeproj` を作成する。ユーザ指示で最初の足場作りは確認とされているため、このフェーズの開始前にユーザに一声かける。

Swift Package ではなく Xcode project を選ぶ理由: codexレビュー指摘どおり、macOS常駐アプリの実態は `.app` bundle (LSUIElement=true) であり、Info.plistとcodesign・Login Item・Automation権限はXcodeプロジェクト (.app ターゲット) で管理するのが健全。Swift Packageの `executableTarget` では単なるCLIバイナリになってしまう。

### Task 1.1: Cargo workspace と ccsplit-logger スケルトン

Files:
- Create: `Cargo.toml`
- Create: `ccsplit-logger/Cargo.toml`
- Create: `ccsplit-logger/src/main.rs`
- Create: `ccsplit-logger/src/cli.rs`
- Create: `.gitignore`

- [x] Step 1: `.gitignore` を作成

```gitignore
target/
.build/
.swiftpm/
DerivedData/
*.xcuserstate
.DS_Store
~/.ccsplit-verify/
```

- [x] Step 2: ルート `Cargo.toml` を作成

```toml
[workspace]
resolver = "2"
members = ["ccsplit-logger"]

[workspace.package]
edition = "2021"
rust-version = "1.75"
license = "MIT"
authors = ["Yoshiteru Negishi"]

[workspace.dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
time = { version = "0.3", features = ["serde", "formatting", "parsing", "macros", "local-offset"] }
```

- [x] Step 3: `ccsplit-logger/Cargo.toml` を作成

```toml
[package]
name = "ccsplit-logger"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true
authors.workspace = true

[dependencies]
anyhow.workspace = true
clap.workspace = true
serde.workspace = true
serde_json.workspace = true
time.workspace = true

[dev-dependencies]
tempfile = "3"
```

- [x] Step 4: `ccsplit-logger/src/main.rs` を作成

```rust
mod cli;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let cli = cli::Cli::parse();
    cli.run()
}
```

- [x] Step 5: `ccsplit-logger/src/cli.rs` を作成

```rust
use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ccsplit-logger", version, about = "Claude Code hook logger for Ghostty pane tracking")]
pub struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    SessionStart,
    Notification,
    Stop,
    PreToolUse,
    UserPromptSubmit,
}

impl Cli {
    pub fn run(self) -> Result<()> {
        match self.command {
            Command::SessionStart => Ok(()),
            Command::Notification => Ok(()),
            Command::Stop => Ok(()),
            Command::PreToolUse => Ok(()),
            Command::UserPromptSubmit => Ok(()),
        }
    }
}
```

- [x] Step 6: ビルド確認

Run: `cargo build -p ccsplit-logger`
Expected: warning OK、error なし

Run: `cargo run -p ccsplit-logger -- --help`
Expected: サブコマンド一覧 (session-start / notification / stop / pre-tool-use / user-prompt-submit) が表示される

- [x] Step 7: コミット

```bash
git add Cargo.toml ccsplit-logger/ .gitignore
git commit
```

メッセージ例: `chore: bootstrap ccsplit-logger Rust workspace and CLI skeleton`

### Task 1.2: ccsplit-app Xcode project スケルトン (ユーザ手動操作が必要)

Files:
- Create: `ccsplit-app/ccsplit-app.xcodeproj/` (ユーザがXcode GUIで作成)
- Create: `ccsplit-app/ccsplit-app/ccsplitApp.swift`
- Create: `ccsplit-app/ccsplit-app/Info.plist` (Xcode自動生成、後でLSUIElementを追加)
- Create: `ccsplit-app/ccsplit-app/ccsplit_app.entitlements`
- Create: `ccsplit-app/ccsplit-appTests/SmokeTests.swift`

- [x] Step 1: ユーザにXcodeでプロジェクト作成を依頼

ユーザへの依頼内容 (口頭・Slack等で提示):
- Xcode を開き File → New → Project...
- Template: macOS → App
- Product Name: `ccsplit-app`
- Team: (任意、個人開発なら空でもビルドは通る)
- Organization Identifier: `com.negipo`
- Bundle Identifier: `com.negipo.ccsplit-app`
- Interface: SwiftUI
- Language: Swift
- Include Tests: チェック
- 保存先: `/Users/negipo/src/github.com/negipo/ccsplit/ccsplit-app/`
- 作成後に `ccsplit-app/ccsplit-app.xcodeproj` があることを確認

Xcode上での追加設定:
- Target `ccsplit-app` → Signing & Capabilities → "Automatically manage signing" はON (開発中は自分のApple ID)
- Info (plist) タブ: `Application is agent (UIElement)` = YES を追加 (`LSUIElement` = true 相当、Dockアイコンを出さない)
- macOS Deployment Target: 13.0 以上
- Capabilities: "App Sandbox" は一旦OFF (AppleScript経由でGhostty制御するため)、もしくは "App Sandbox" ON + `com.apple.security.automation.apple-events` を entitlementに追加して `com.apple.Ghostty` を許可。前者の方が確実なのでMVPではOFF

完了確認:
Run: `ls ccsplit-app/ccsplit-app.xcodeproj/project.pbxproj`
Expected: 存在する

- [x] Step 2: 生成された `ccsplit-app/ccsplit-app/ccsplit_appApp.swift` (Xcode自動命名) を `ccsplitApp.swift` にリネームし、中身を差し替える

```swift
import SwiftUI

@main
struct CcsplitApp: App {
    var body: some Scene {
        MenuBarExtra("ccsplit", systemImage: "bubble.left.and.bubble.right") {
            Text("ccsplit (skeleton)")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
```

Xcode GUIでの設定項目 (エージェントからは操作できないため、ユーザに手動で依頼):
- プロジェクトナビゲータで既存の `ContentView.swift` があれば削除 (MenuBarExtraベースなので不要)
- Info.plist に `Application is agent (UIElement)` を `YES` で追加済みであることを再確認

- [x] Step 3: SmokeTests.swift

Xcodeが自動生成した `ccsplit_appTests.swift` を `SmokeTests.swift` にリネームし、中身を差し替え:

```swift
import XCTest
@testable import ccsplit_app

final class SmokeTests: XCTestCase {
    func testAlwaysPasses() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

注: `@testable import ccsplit_app` はProduct Moduleのimport。Xcode のTargetにTest対象を追加して初めて通る。

- [x] Step 4: CLIビルド

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -configuration Debug test`
Expected: SmokeTestsが1つpass

- [x] Step 5: 手動起動確認

Run (ビルド成果物のパス):
```bash
APP=$(xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -showBuildSettings -configuration Debug | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')
open "$APP/ccsplit-app.app"
```
Expected: メニューバーにbubbleアイコンが出現、Dockアイコンは出ない (LSUIElement効いている)、クリックで "ccsplit (skeleton)" と Quit が見える

LSUIElementが効いていない場合: Info.plistに `<key>LSUIElement</key><true/>` を手動で追加する

- [x] Step 6: コミット

```bash
git add ccsplit-app/
git commit
```

メッセージ例: `chore: bootstrap ccsplit-app Xcode project with MenuBarExtra skeleton`

注: Xcode projectファイル (`project.pbxproj`) はバイナリ(テキストplist) で merge conflict の温床だが、今は1人開発なのでそのままコミットする。将来の複数人開発時はXcodeGen等を検討。

---

## フェーズ2: ccsplit-logger 核コンポーネント

設計ドキュメントのlogger側ロジックを、I/O境界をモックしやすい形で実装する。

設計上の不変条件: 「Hookの同期パスにAppleScriptやgitのような重い処理を置かない (常に背景detach)」。Task 2.0 でself-detach機構を先に用意してから、本体処理は必ず子プロセス側で走らせる。

### Task 2.0: self-detach 機構 (ccsplit-logger 共通)

Claude Code のHookは `type: "command"` の場合、呼び出したプロセスが終了するまで待つ可能性が高い。AppleScript列挙 (50〜150ms) や git (数〜数十ms)、リトライ (最大500ms) を同期パスに置くとClaude Code起動・ターン進行が目に見えて遅くなる。

方針: ccsplit-logger は起動直後に「stdin payload を吸い出し → 同じ実行ファイルを `CCSPLIT_LOGGER_DETACHED=1` env 付き + 同引数で spawn → stdin に payload をpipe → 親は即 exit」する。子プロセスは env の検出で detach済みと判定し、本処理に進む。これにより hook 同期パスは数ms (プロセスspawn + payload pipe書き込み) で完了する。

Files:
- Create: `ccsplit-logger/src/detach.rs`
- Modify: `ccsplit-logger/src/main.rs` (最初の関数呼び出しとしてdetachを挟む)
- Modify: `ccsplit-logger/src/lib.rs`
- Create: `ccsplit-logger/tests/detach.rs`

- [x] Step 1: テスト (detach検出ロジックの純部分)

```rust
use ccsplit_logger::detach::{is_detached_child, child_env_marker};

#[test]
fn is_detached_child_false_when_env_absent() {
    std::env::remove_var(child_env_marker());
    assert!(!is_detached_child());
}

#[test]
fn is_detached_child_true_when_env_present() {
    std::env::set_var(child_env_marker(), "1");
    assert!(is_detached_child());
    std::env::remove_var(child_env_marker());
}
```

- [x] Step 2: `ccsplit-logger/src/detach.rs` を作成

```rust
use anyhow::Result;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

pub const CHILD_ENV: &str = "CCSPLIT_LOGGER_DETACHED";

pub fn child_env_marker() -> &'static str { CHILD_ENV }

pub fn is_detached_child() -> bool {
    std::env::var(CHILD_ENV).is_ok()
}

pub fn detach_and_exit_parent() -> Result<()> {
    let mut payload = Vec::new();
    std::io::stdin().read_to_end(&mut payload)?;

    let exe = std::env::current_exe()?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut child = Command::new(exe)
        .args(&args)
        .env(CHILD_ENV, "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(&payload)?;
    }
    std::process::exit(0);
}
```

子側で setsid を呼び sessionleader 化することで、親exit後もlaunchdにreparentされclaude codeのhookからも完全に切り離される:

```rust
#[cfg(unix)]
pub fn become_session_leader() {
    extern "C" { fn setsid() -> i32; }
    unsafe { let _ = setsid(); }
}
```

- [x] Step 3: `main.rs` の冒頭で分岐

detach はhook由来の5コマンド (`session-start` / `notification` / `stop` / `pre-tool-use` / `user-prompt-submit`) のみに適用する。管理系CLI (`--help` / `install` / 将来追加するもの) はフォアグラウンド実行を維持し、stdout/stderr をそのまま出す。

```rust
mod cli;

use anyhow::Result;
use clap::Parser;
use ccsplit_logger::detach::{become_session_leader, detach_and_exit_parent, is_detached_child};

fn main() -> Result<()> {
    let cli = cli::Cli::parse();
    if cli.needs_detach() {
        if !is_detached_child() {
            detach_and_exit_parent()?;
            unreachable!();
        }
        become_session_leader();
    }
    cli.run()
}
```

`cli.rs` 側で `needs_detach` を定義:

```rust
impl Cli {
    pub fn needs_detach(&self) -> bool {
        matches!(self.command,
            Command::SessionStart
            | Command::Notification
            | Command::Stop
            | Command::PreToolUse
            | Command::UserPromptSubmit
        )
    }
}
```

- [x] Step 3.5: `needs_detach` のテスト

```rust
// tests/cli_detach.rs
use ccsplit_logger::cli::Cli;
use clap::Parser;

#[test]
fn hook_commands_require_detach() {
    for sub in ["session-start", "notification", "stop", "pre-tool-use", "user-prompt-submit"] {
        let cli = Cli::try_parse_from(["ccsplit-logger", sub]).unwrap();
        assert!(cli.needs_detach(), "{} should detach", sub);
    }
}

#[test]
fn install_does_not_detach() {
    let cli = Cli::try_parse_from(["ccsplit-logger", "install"]).unwrap();
    assert!(!cli.needs_detach());
}
```

`cli` モジュールを `pub mod cli;` として lib.rs からexposeする必要がある。

注: `install` コマンドは Task 7.2 で追加。この検証は Task 2.0 段階ではまだ存在しないので、その行だけTask 7.2 完了後に有効化する。`#[cfg(any())]` でコメントアウトしておくか、当面は hook 5種のみテストして後で install を追加する。

- [x] Step 4: テスト通過

Run: `cargo test -p ccsplit-logger --test detach`
Expected: 2 passed

- [x] Step 5: 実機計測

settings.jsonの検証用hookに `/path/to/ccsplit-logger session-start` を仮登録し、以下を計測:

Run: `time (echo '{"session_id":"t","cwd":"/tmp"}' | ccsplit-logger session-start)`
Expected: `real` が 50ms 未満 (目標は10〜30ms)

子プロセス側の処理は別途background で走っているので、`\cat ~/Library/Application\ Support/ccsplit/events/$(date +%Y-%m-%d).jsonl` で数秒以内にsession_start行が追加されていることを確認。

- [x] Step 6: コミット

メッセージ例: `feat(logger): detach from hook sync path via self-spawn plus setsid`

### Task 2.1: Event スキーマ

Files:
- Create: `ccsplit-logger/src/event.rs`
- Create: `ccsplit-logger/tests/event_serde.rs`
- Modify: `ccsplit-logger/src/main.rs` (`mod event;` 追加)

- [x] Step 1: テスト `ccsplit-logger/tests/event_serde.rs` を作成

```rust
use ccsplit_logger::event::{Event, EventKind};

#[test]
fn session_start_serializes_to_expected_json() {
    let ev = Event {
        ts: "2026-04-16T09:12:34.567Z".to_string(),
        kind: EventKind::SessionStart {
            session_id: "abc".to_string(),
            terminal_id: Some("B9BE".to_string()),
            cwd: "/tmp".to_string(),
            git_branch: Some("main".to_string()),
            claude_pid: Some(12345),
            claude_start_time: Some("Wed Apr 16 09:12:34 2026".to_string()),
            claude_comm: Some("claude".to_string()),
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"event\":\"session_start\""));
    assert!(json.contains("\"session_id\":\"abc\""));
    assert!(json.contains("\"terminal_id\":\"B9BE\""));
    assert!(json.contains("\"claude_pid\":12345"));
}

#[test]
fn notification_serializes_without_extra_fields() {
    let ev = Event {
        ts: "2026-04-16T09:13:45.890Z".to_string(),
        kind: EventKind::Notification {
            session_id: "abc".to_string(),
            message: "approval needed".to_string(),
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"event\":\"notification\""));
    assert!(!json.contains("\"terminal_id\""));
}

#[test]
fn terminal_id_null_is_serialized_as_null_not_missing() {
    let ev = Event {
        ts: "2026-04-16T09:12:34.567Z".to_string(),
        kind: EventKind::SessionStart {
            session_id: "abc".to_string(),
            terminal_id: None,
            cwd: "/tmp".to_string(),
            git_branch: None,
            claude_pid: None,
            claude_start_time: None,
            claude_comm: None,
        },
    };
    let json = serde_json::to_string(&ev).unwrap();
    assert!(json.contains("\"terminal_id\":null"));
    assert!(json.contains("\"git_branch\":null"));
    assert!(json.contains("\"claude_pid\":null"));
}
```

- [x] Step 2: テスト失敗確認

Run: `cargo test -p ccsplit-logger --test event_serde`
Expected: コンパイルエラー (event module 未定義)

- [x] Step 3: `ccsplit-logger/src/event.rs` を作成

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub ts: String,
    #[serde(flatten)]
    pub kind: EventKind,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum EventKind {
    SessionStart {
        session_id: String,
        terminal_id: Option<String>,
        cwd: String,
        git_branch: Option<String>,
        claude_pid: Option<u32>,
        claude_start_time: Option<String>,
        claude_comm: Option<String>,
    },
    Notification {
        session_id: String,
        message: String,
    },
    Stop {
        session_id: String,
    },
    PreToolUse {
        session_id: String,
        tool: Option<String>,
    },
    UserPromptSubmit {
        session_id: String,
    },
}
```

`terminal_id: Option<String>` がシリアライズ時に `null` として出るように、`#[serde(skip_serializing_if)]` は付けない。

- [x] Step 4: main.rsとlib.rsの構造調整

`ccsplit-logger/src/main.rs` と同階層に `ccsplit-logger/src/lib.rs` を作成し、integration testから参照可能にする:

```rust
// ccsplit-logger/src/lib.rs
pub mod event;
```

`ccsplit-logger/Cargo.toml` の `[package]` に以下を追加:
```toml
[lib]
name = "ccsplit_logger"
path = "src/lib.rs"

[[bin]]
name = "ccsplit-logger"
path = "src/main.rs"
```

`main.rs` は `use ccsplit_logger::...` に切り替える。

- [x] Step 5: テスト通過確認

Run: `cargo test -p ccsplit-logger --test event_serde`
Expected: 3 tests passed

- [x] Step 6: コミット

```bash
git add ccsplit-logger/
git commit
```

メッセージ例: `feat(logger): add event schema with JSON serialization`

### Task 2.2: LogPath - イベントログファイルパス解決

Files:
- Create: `ccsplit-logger/src/log_path.rs`
- Create: `ccsplit-logger/tests/log_path.rs`
- Modify: `ccsplit-logger/src/lib.rs`

- [x] Step 1: テスト

```rust
use ccsplit_logger::log_path::{events_dir, log_file_for};
use time::macros::datetime;

#[test]
fn events_dir_is_application_support_ccsplit_events() {
    let home = std::env::var("HOME").unwrap();
    let dir = events_dir().unwrap();
    assert_eq!(dir, std::path::PathBuf::from(format!("{}/Library/Application Support/ccsplit/events", home)));
}

#[test]
fn log_file_for_uses_yyyy_mm_dd_jsonl_in_local_time() {
    let dt = datetime!(2026-04-16 09:12:34 UTC);
    let p = log_file_for(dt.date()).unwrap();
    let s = p.to_string_lossy();
    assert!(s.ends_with("events/2026-04-16.jsonl"));
}
```

- [x] Step 2: テスト失敗確認

Run: `cargo test -p ccsplit-logger --test log_path`
Expected: コンパイルエラー

- [x] Step 3: `ccsplit-logger/src/log_path.rs` を作成

```rust
use anyhow::{anyhow, Result};
use std::path::PathBuf;
use time::{Date, OffsetDateTime, UtcOffset};

pub fn events_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").map_err(|_| anyhow!("HOME not set"))?;
    Ok(PathBuf::from(home).join("Library/Application Support/ccsplit/events"))
}

pub fn log_file_for(date: Date) -> Result<PathBuf> {
    let name = format!(
        "{:04}-{:02}-{:02}.jsonl",
        date.year(),
        u8::from(date.month()),
        date.day()
    );
    Ok(events_dir()?.join(name))
}

pub fn log_file_for_now() -> Result<PathBuf> {
    let offset = UtcOffset::current_local_offset().unwrap_or(UtcOffset::UTC);
    let now = OffsetDateTime::now_utc().to_offset(offset);
    log_file_for(now.date())
}
```

- [x] Step 4: `ccsplit-logger/src/lib.rs` に `pub mod log_path;` 追加

- [x] Step 5: テスト通過

Run: `cargo test -p ccsplit-logger --test log_path`
Expected: 2 passed

- [x] Step 6: コミット

```bash
git add ccsplit-logger/
git commit
```

メッセージ例: `feat(logger): resolve event log file path under Application Support`

### Task 2.3: LogWriter - append jsonl

Files:
- Create: `ccsplit-logger/src/log_writer.rs`
- Create: `ccsplit-logger/tests/log_writer.rs`
- Modify: `ccsplit-logger/src/lib.rs`

- [x] Step 1: テスト

```rust
use ccsplit_logger::event::{Event, EventKind};
use ccsplit_logger::log_writer::append_event_to;
use tempfile::tempdir;

#[test]
fn append_creates_file_with_single_line() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("2026-04-16.jsonl");
    let ev = Event {
        ts: "2026-04-16T00:00:00.000Z".to_string(),
        kind: EventKind::Stop { session_id: "abc".to_string() },
    };
    append_event_to(&path, &ev).unwrap();
    let content = std::fs::read_to_string(&path).unwrap();
    assert_eq!(content.lines().count(), 1);
    assert!(content.ends_with('\n'));
}

#[test]
fn append_two_events_produces_two_lines() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("d.jsonl");
    for sid in ["a", "b"] {
        let ev = Event {
            ts: "2026-04-16T00:00:00.000Z".to_string(),
            kind: EventKind::Stop { session_id: sid.to_string() },
        };
        append_event_to(&path, &ev).unwrap();
    }
    let content = std::fs::read_to_string(&path).unwrap();
    assert_eq!(content.lines().count(), 2);
    assert!(content.lines().next().unwrap().contains("\"session_id\":\"a\""));
    assert!(content.lines().nth(1).unwrap().contains("\"session_id\":\"b\""));
}

#[test]
fn append_creates_parent_dir_if_missing() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("nested/deeper/file.jsonl");
    let ev = Event {
        ts: "2026-04-16T00:00:00.000Z".to_string(),
        kind: EventKind::Stop { session_id: "abc".to_string() },
    };
    append_event_to(&path, &ev).unwrap();
    assert!(path.exists());
}
```

- [x] Step 2: テスト失敗確認

Run: `cargo test -p ccsplit-logger --test log_writer`
Expected: コンパイルエラー

- [x] Step 3: `ccsplit-logger/src/log_writer.rs` を作成

```rust
use crate::event::Event;
use anyhow::{Context, Result};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::Path;

pub fn append_event_to(path: &Path, ev: &Event) -> Result<()> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent).with_context(|| format!("mkdir -p {}", parent.display()))?;
    }
    let mut f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("open {}", path.display()))?;
    let line = serde_json::to_string(ev)?;
    f.write_all(line.as_bytes())?;
    f.write_all(b"\n")?;
    Ok(())
}
```

- [x] Step 4: `ccsplit-logger/src/lib.rs` に `pub mod log_writer;` 追加

- [x] Step 5: テスト通過

Run: `cargo test -p ccsplit-logger --test log_writer`
Expected: 3 passed

- [x] Step 6: コミット

メッセージ例: `feat(logger): append events as jsonl with O_APPEND semantics`

### Task 2.4: 時刻 & タイムスタンプ生成ヘルパ

Files:
- Create: `ccsplit-logger/src/timestamp.rs`
- Modify: `ccsplit-logger/src/lib.rs`

- [x] Step 1: テスト (ドキュメントテストでOK、外形ルールのみ)

```rust
// ccsplit-logger/src/timestamp.rs 内に #[cfg(test)] モジュールを置く
#[cfg(test)]
mod tests {
    use super::now_iso8601;

    #[test]
    fn format_matches_iso8601_utc_millis() {
        let s = now_iso8601();
        // YYYY-MM-DDTHH:MM:SS.mmmZ
        assert_eq!(s.len(), 24);
        assert!(s.ends_with('Z'));
        assert_eq!(&s[4..5], "-");
        assert_eq!(&s[7..8], "-");
        assert_eq!(&s[10..11], "T");
    }
}
```

- [x] Step 2: `ccsplit-logger/src/timestamp.rs` 作成

```rust
use time::format_description::well_known::Iso8601;
use time::OffsetDateTime;

pub fn now_iso8601() -> String {
    let now = OffsetDateTime::now_utc();
    now.format(&Iso8601::DEFAULT)
        .unwrap_or_else(|_| "1970-01-01T00:00:00.000Z".to_string())
}
```

注: Iso8601::DEFAULT は24文字固定にならない可能性がある。テスト失敗時は format_description! を用いた固定フォーマットに置き換える。

フォールバック (テストが落ちたら):
```rust
use time::macros::format_description;
use time::OffsetDateTime;

pub fn now_iso8601() -> String {
    let fmt = format_description!("[year]-[month]-[day]T[hour]:[minute]:[second].[subsecond digits:3]Z");
    OffsetDateTime::now_utc().format(fmt).unwrap_or_default()
}
```

- [x] Step 3: lib.rs に追加

- [x] Step 4: テスト通過 (必要ならフォールバック適用)

Run: `cargo test -p ccsplit-logger`
Expected: all tests pass

- [x] Step 5: コミット

メッセージ例: `feat(logger): add ISO8601 UTC timestamp helper`

### Task 2.5: Git branch 取得

Files:
- Create: `ccsplit-logger/src/git.rs`
- Modify: `ccsplit-logger/src/lib.rs`

- [x] Step 1: テスト設計

CLI呼び出しを直接テストするのは環境依存なので、関数は `git_branch_via_command(cmd_runner, cwd)` のようにコマンド実行を抽象化してテスト可能にする。

```rust
// src/git.rs
#[cfg(test)]
mod tests {
    use super::*;

    struct FakeRunner(Result<String, anyhow::Error>);

    impl CommandRunner for FakeRunner {
        fn run(&self, _prog: &str, _args: &[&str]) -> anyhow::Result<String> {
            self.0.as_ref().map(|s| s.clone()).map_err(|e| anyhow::anyhow!(e.to_string()))
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
        let runner = FakeRunner(Err(anyhow::anyhow!("fatal: not a git repo")));
        let b = git_branch(&runner, "/tmp").unwrap();
        assert_eq!(b, None);
    }

    #[test]
    fn returns_none_on_detached_head_head() {
        let runner = FakeRunner(Ok("HEAD\n".to_string()));
        let b = git_branch(&runner, "/tmp").unwrap();
        assert_eq!(b, None);
    }
}
```

- [x] Step 2: `ccsplit-logger/src/git.rs` 作成

```rust
use anyhow::Result;

pub trait CommandRunner {
    fn run(&self, prog: &str, args: &[&str]) -> Result<String>;
}

pub struct RealRunner;

impl CommandRunner for RealRunner {
    fn run(&self, prog: &str, args: &[&str]) -> Result<String> {
        let out = std::process::Command::new(prog).args(args).output()?;
        if !out.status.success() {
            anyhow::bail!("{} {:?} failed: {}", prog, args, String::from_utf8_lossy(&out.stderr));
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
```

- [x] Step 3: lib.rs に追加 + テスト通過

Run: `cargo test -p ccsplit-logger`
Expected: all tests pass

- [x] Step 4: コミット

メッセージ例: `feat(logger): query git branch for session_start payload`

### Task 2.6: Claude process metadata (ps + comm pattern 判定)

Files:
- Create: `ccsplit-logger/src/claude_proc.rs`
- Modify: `ccsplit-logger/src/lib.rs`

注:
- ccsplit-loggerのdetach機構が入った時点で親は launchd / 子shell。よって `current_ppid()` や `getppid()` は Claude を指さない。設計 & 検証A の想定 (hook script 内で ps -p $PPID を取得) は hook script で取るもの。ccsplit-logger起動時には既に detach済みで親が変わっている。claude_pid 系は logger がforkする前 (hook内 shell) で抽出する必要がある
- 修正: Claude Code hook は `command` を直接spawnするため、ccsplit-loggerが最初に起動される時点では `$PPID = claude` (もしくはnode/bun等) である。Task 2.0 の self-detach は「current_exe を再spawn」するので、親プロセスの `$PPID` と `getppid()` の値は子プロセス内では親 (初代logger) を指す。したがって初代logger が claude_pid を確保してから子に env 渡しする形で継承する

claude_pid 取得戦略:
- 初代logger 起動時 (is_detached_child() == false) で `ps -p <getppid()> -o pid=,lstart=,comm=,command=` を実行
- 結果から CLAUDE_COMM_PATTERNS に含まれるcomm/commandかを判定、該当したら env `CCSPLIT_CLAUDE_PID=<pid>`, `CCSPLIT_CLAUDE_START=<lstart>`, `CCSPLIT_CLAUDE_COMM=<comm>` を子にも渡す
- 該当しなければ、親方向に最大5段遡り (getppid → ppid → ...) して claude-like を探す
- いずれもヒットしなければ env 未設定 (= claude_pid null)
- 子 (detached) は env から claude_* を読み取り、session_start event に記録

CLAUDE_COMM_PATTERNS は検証A結果に基づいて初期値を決める。観測候補: `claude`, `claude-code`, `node`, `bun`, `deno`。`comm` (basename) と `command` (full path with args) の両方でsubstring matchする:

```rust
pub const CLAUDE_PATTERNS: &[&str] = &[
    "claude",       // node/bun ラッパー名が "claude" なら一致
    "claude-code",  // 将来のbinary名
];

// 検証Aで 'node' / 'bun' がobserved commだった場合は、full commandに "/claude" を含むか等の二次条件を追加する
pub fn is_claude_like(comm: &str, full_command: &str) -> bool {
    let haystack_comm = comm.to_ascii_lowercase();
    let haystack_cmd = full_command.to_ascii_lowercase();
    CLAUDE_PATTERNS.iter().any(|p| haystack_comm.contains(&p.to_ascii_lowercase())
        || haystack_cmd.contains(&p.to_ascii_lowercase()))
}
```

- [x] Step 1: テスト

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::git::CommandRunner;

    struct Fake(String);
    impl CommandRunner for Fake {
        fn run(&self, _p: &str, _a: &[&str]) -> anyhow::Result<String> { Ok(self.0.clone()) }
    }

    #[test]
    fn parses_ps_output_with_command() {
        // ps -p <pid> -o pid=,lstart=,comm=,command=
        let r = Fake("12345 Wed Apr 16 09:12:34 2026 claude /opt/homebrew/bin/claude --verbose\n".into());
        let info = query_proc(&r, 12345).unwrap();
        assert_eq!(info.pid, 12345);
        assert_eq!(info.lstart, "Wed Apr 16 09:12:34 2026");
        assert_eq!(info.comm, "claude");
        assert!(info.command.contains("/claude"));
    }

    #[test]
    fn is_claude_like_accepts_claude_comm() {
        assert!(is_claude_like("claude", "claude"));
    }

    #[test]
    fn is_claude_like_accepts_node_with_claude_in_command() {
        assert!(is_claude_like("node", "/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude"));
    }

    #[test]
    fn is_claude_like_rejects_plain_zsh() {
        assert!(!is_claude_like("zsh", "-zsh"));
    }
}
```

- [x] Step 2: `ccsplit-logger/src/claude_proc.rs` 実装

```rust
use crate::git::CommandRunner;
use anyhow::{anyhow, Result};

pub const CLAUDE_PATTERNS: &[&str] = &["claude", "claude-code"];

#[derive(Debug, Clone)]
pub struct ProcInfo {
    pub pid: u32,
    pub lstart: String,
    pub comm: String,
    pub command: String,
}

pub fn query_proc(runner: &impl CommandRunner, pid: u32) -> Result<ProcInfo> {
    let out = runner.run("ps", &["-p", &pid.to_string(), "-o", "pid=,lstart=,comm=,command="])?;
    parse_ps_line(&out, pid)
}

fn parse_ps_line(s: &str, expected_pid: u32) -> Result<ProcInfo> {
    let line = s.trim_end_matches('\n').trim_start();
    let mut tokens = line.split_whitespace();
    let pid_str = tokens.next().ok_or_else(|| anyhow!("empty ps output"))?;
    let pid: u32 = pid_str.parse()?;
    if pid != expected_pid { return Err(anyhow!("pid mismatch")); }
    let mut lstart_parts = Vec::new();
    for _ in 0..5 {
        lstart_parts.push(tokens.next().ok_or_else(|| anyhow!("incomplete lstart"))?);
    }
    let lstart = lstart_parts.join(" ");
    let comm = tokens.next().ok_or_else(|| anyhow!("missing comm"))?.to_string();
    let command = tokens.collect::<Vec<_>>().join(" ");
    Ok(ProcInfo { pid, lstart, comm, command })
}

pub fn is_claude_like(comm: &str, command: &str) -> bool {
    let c = comm.to_ascii_lowercase();
    let full = command.to_ascii_lowercase();
    CLAUDE_PATTERNS.iter().any(|p| {
        let pl = p.to_ascii_lowercase();
        c.contains(&pl) || full.contains(&pl)
    })
}

pub fn find_claude_proc<R: CommandRunner>(runner: &R, start_pid: u32, max_depth: u32) -> Option<ProcInfo> {
    let mut pid = start_pid;
    for _ in 0..=max_depth {
        let info = match query_proc(runner, pid) {
            Ok(i) => i,
            Err(_) => return None,
        };
        if is_claude_like(&info.comm, &info.command) {
            return Some(info);
        }
        match ppid_of(runner, pid) {
            Some(p) if p > 0 && p != pid => pid = p,
            _ => return None,
        }
    }
    None
}

fn ppid_of<R: CommandRunner>(runner: &R, pid: u32) -> Option<u32> {
    runner.run("ps", &["-p", &pid.to_string(), "-o", "ppid="])
        .ok()
        .and_then(|s| s.trim().parse().ok())
}
```

- [x] Step 3: 親側 (is_detached_child() == false) での claude_pid 抽出を `detach.rs` と連携

`detach_and_exit_parent()` を拡張して、自己spawn前にclaude_procを解決し、envとして子に渡す:

```rust
// detach.rs 内の detach_and_exit_parent を拡張
use crate::claude_proc::{find_claude_proc, CLAUDE_PATTERNS};
use crate::git::RealRunner;

pub fn detach_and_exit_parent() -> Result<()> {
    let mut payload = Vec::new();
    std::io::stdin().read_to_end(&mut payload)?;

    let mut cmd = Command::new(std::env::current_exe()?);
    cmd.args(std::env::args().skip(1))
        .env(CHILD_ENV, "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let ppid = parent_pid();
    if let Some(info) = find_claude_proc(&RealRunner, ppid, 5) {
        cmd.env("CCSPLIT_CLAUDE_PID", info.pid.to_string())
           .env("CCSPLIT_CLAUDE_START", &info.lstart)
           .env("CCSPLIT_CLAUDE_COMM", &info.comm);
    }

    let mut child = cmd.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(&payload)?;
    }
    std::process::exit(0);
}

#[cfg(unix)]
fn parent_pid() -> u32 {
    extern "C" { fn getppid() -> i32; }
    unsafe { getppid() as u32 }
}
```

子側 (session_start command 内) では `std::env::var("CCSPLIT_CLAUDE_PID")` を読む。

- [x] Step 4: lib.rs 更新

- [x] Step 5: テスト通過

Run: `cargo test -p ccsplit-logger`
Expected: all tests pass

- [x] Step 6: コミット

メッセージ例: `feat(logger): detect Claude process across comm patterns and pass via env`

### Task 2.7: Ghostty terminal 列挙と絞り込み

Files:
- Create: `ccsplit-logger/src/ghostty.rs`
- Modify: `ccsplit-logger/src/lib.rs`

フェーズ0検証B 結果により、リトライ回数とリトライ間隔を調整する。初期値は設計通り「最大5回 × 100ms」。

- [x] Step 1: AppleScriptテキスト定数と parser をテストファースト

```rust
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
            Term { id: "T1".into(), name: "⠂ Claude Code".into(), wd: "/foo".into() },
            Term { id: "T2".into(), name: "zsh".into(), wd: "/foo".into() },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }

    #[test]
    fn match_none_when_no_claude_code() {
        let terms = vec![
            Term { id: "T1".into(), name: "zsh".into(), wd: "/foo".into() },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::None);
    }

    #[test]
    fn match_multiple_when_same_cwd_two_claude() {
        let terms = vec![
            Term { id: "T1".into(), name: "⠂ Claude Code".into(), wd: "/foo".into() },
            Term { id: "T2".into(), name: "✳ Claude Code".into(), wd: "/foo".into() },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Multiple);
    }

    #[test]
    fn match_handles_spinner_prefix() {
        let terms = vec![
            Term { id: "T1".into(), name: "⠐ Claude Code".into(), wd: "/foo".into() },
            Term { id: "T2".into(), name: "zsh".into(), wd: "/foo".into() },
        ];
        let m = pick_match(&terms, "/foo");
        assert_eq!(m, MatchResult::Unique("T1".into()));
    }
}
```

- [x] Step 2: `ccsplit-logger/src/ghostty.rs` 作成

```rust
use crate::git::CommandRunner;
use anyhow::Result;
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
                if let Some(v) = part.strip_prefix("id=") { id = Some(v.to_string()); }
                else if let Some(v) = part.strip_prefix("name=") { name = Some(v.to_string()); }
                else if let Some(v) = part.strip_prefix("wd=") { wd = Some(v.to_string()); }
            }
            Some(Term { id: id?, name: name?, wd: wd? })
        })
        .collect()
}

pub fn pick_match(terms: &[Term], cwd: &str) -> MatchResult {
    let cands: Vec<&Term> = terms.iter()
        .filter(|t| t.wd == cwd && t.name.contains("Claude Code"))
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
    max_attempts: usize,
    interval: Duration,
) -> Option<String> {
    for i in 0..max_attempts {
        if i > 0 { sleep(interval); }
        let Ok(terms) = enumerate_terminals(runner) else { continue };
        if let MatchResult::Unique(id) = pick_match(&terms, cwd) {
            return Some(id);
        }
    }
    None
}
```

- [x] Step 3: lib.rs更新

- [x] Step 4: テスト通過

Run: `cargo test -p ccsplit-logger`
Expected: all tests pass

- [x] Step 5: コミット

メッセージ例: `feat(logger): enumerate Ghostty terminals via AppleScript and match by cwd+name`

### Task 2.8: session-start コマンド結線

Files:
- Create: `ccsplit-logger/src/commands/mod.rs`
- Create: `ccsplit-logger/src/commands/session_start.rs`
- Modify: `ccsplit-logger/src/cli.rs`
- Modify: `ccsplit-logger/src/lib.rs`

Hook payload は stdin JSON:
```json
{"session_id":"abc","cwd":"/foo","hook_event_name":"SessionStart",...}
```

- [x] Step 1: stdin payload parse のテスト

```rust
// ccsplit-logger/src/commands/session_start.rs 内
#[cfg(test)]
mod tests {
    use super::HookPayload;

    #[test]
    fn parses_minimal_session_start_payload() {
        let json = r#"{"session_id":"abc","cwd":"/foo"}"#;
        let p: HookPayload = serde_json::from_str(json).unwrap();
        assert_eq!(p.session_id, "abc");
        assert_eq!(p.cwd, "/foo");
    }

    #[test]
    fn tolerates_extra_fields() {
        let json = r#"{"session_id":"abc","cwd":"/foo","hook_event_name":"SessionStart","extra":123}"#;
        let p: HookPayload = serde_json::from_str(json).unwrap();
        assert_eq!(p.session_id, "abc");
    }
}
```

- [x] Step 2: 実装

`ccsplit-logger/src/commands/mod.rs`:
```rust
pub mod session_start;
pub mod notification;
pub mod stop;
pub mod pre_tool_use;
pub mod user_prompt_submit;
```

`ccsplit-logger/src/commands/session_start.rs`:
```rust
use crate::event::{Event, EventKind};
use crate::ghostty::find_terminal_id_with_retry;
use crate::git::{git_branch, RealRunner};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;
use std::time::Duration;

#[derive(Debug, Deserialize)]
pub struct HookPayload {
    pub session_id: String,
    pub cwd: String,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let payload: HookPayload = serde_json::from_str(&buf)?;

    let runner = RealRunner;

    let terminal_id = find_terminal_id_with_retry(&runner, &payload.cwd, 5, Duration::from_millis(100));

    let git_branch = git_branch(&runner, &payload.cwd).unwrap_or(None);

    let claude_pid = std::env::var("CCSPLIT_CLAUDE_PID").ok().and_then(|s| s.parse().ok());
    let claude_start_time = std::env::var("CCSPLIT_CLAUDE_START").ok();
    let claude_comm = std::env::var("CCSPLIT_CLAUDE_COMM").ok();

    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::SessionStart {
            session_id: payload.session_id,
            terminal_id,
            cwd: payload.cwd,
            git_branch,
            claude_pid,
            claude_start_time,
            claude_comm,
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
```

claude_pid 系は Task 2.0 の self-detach で親プロセス (= hook直下のlogger) で解決した結果が env で渡ってきている。親が解決できなかった場合は env 未設定 = null記録。これにより session-start 子プロセスは「親で集めた情報の取りまとめ+I/Oだけ」を行う。

- [x] Step 3: `cli.rs` から `Command::SessionStart => commands::session_start::run()` に結線

- [x] Step 4: Hook手動テスト

`~/.claude/settings.json` に `ccsplit-logger session-start` を `SessionStart` に仮登録し、新しいpaneで `claude` を実行。

`~/Library/Application Support/ccsplit/events/<今日>.jsonl` に session_start 行が1行入っていることを確認:

Run: `\cat ~/Library/Application\ Support/ccsplit/events/$(date +%Y-%m-%d).jsonl`
Expected: `{"ts":"...","event":"session_start","session_id":"...","terminal_id":"...","cwd":"...","git_branch":"po/ccsplit-impl-plan","claude_pid":...,"claude_start_time":"...","claude_comm":"claude"}`

失敗時のトリアージ:
- `terminal_id:null` → フェーズ0検証Bの結果を踏まえリトライ設定見直し
- `claude_pid:null` → フェーズ0検証Aの親遡りロジック追加
- jsonl未生成 → パス解決の問題、log_path テストの確認

確認後、settings.jsonの仮hookは削除。

- [x] Step 5: コミット

メッセージ例: `feat(logger): implement session-start command that writes full payload to jsonl`

### Task 2.9: 残り4コマンド (notification / stop / pre_tool_use / user_prompt_submit)

いずれも Task 2.0 の self-detach 経由で子プロセス側で走る (本処理は hook同期パスを外れる)。AppleScriptもclaude_pid解決も不要なので、notification/stop系の子プロセスは極めて軽く動作する。

Files:
- Create: `ccsplit-logger/src/commands/notification.rs`
- Create: `ccsplit-logger/src/commands/stop.rs`
- Create: `ccsplit-logger/src/commands/pre_tool_use.rs`
- Create: `ccsplit-logger/src/commands/user_prompt_submit.rs`
- Modify: `ccsplit-logger/src/cli.rs`

- [x] Step 1: Notification実装

```rust
// commands/notification.rs
use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;

#[derive(Debug, Deserialize)]
struct Payload {
    session_id: String,
    #[serde(default)]
    message: Option<String>,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::Notification {
            session_id: p.session_id,
            message: p.message.unwrap_or_default(),
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
```

- [x] Step 2: Stop / PreToolUse / UserPromptSubmit も同様にpayloadだけ拾ってjsonl追記

`commands/stop.rs`:
```rust
use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;

#[derive(Debug, Deserialize)]
struct Payload { session_id: String }

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::Stop { session_id: p.session_id },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
```

`commands/pre_tool_use.rs`:
```rust
use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;

#[derive(Debug, Deserialize)]
struct Payload {
    session_id: String,
    #[serde(default)]
    tool_name: Option<String>,
}

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::PreToolUse {
            session_id: p.session_id,
            tool: p.tool_name,
        },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
```

`commands/user_prompt_submit.rs`:
```rust
use crate::event::{Event, EventKind};
use crate::log_path::log_file_for_now;
use crate::log_writer::append_event_to;
use crate::timestamp::now_iso8601;
use anyhow::Result;
use serde::Deserialize;
use std::io::Read;

#[derive(Debug, Deserialize)]
struct Payload { session_id: String }

pub fn run() -> Result<()> {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf)?;
    let p: Payload = serde_json::from_str(&buf)?;
    let ev = Event {
        ts: now_iso8601(),
        kind: EventKind::UserPromptSubmit { session_id: p.session_id },
    };
    append_event_to(&log_file_for_now()?, &ev)?;
    Ok(())
}
```

- [x] Step 3: cli.rsに4コマンドを結線

- [x] Step 4: ユニットテストでそれぞれpayload parseを確認 (各コマンドの tests モジュールに追加)

- [x] Step 5: 全Hook手動確認

settings.jsonに5hook全部登録 → claude起動・何か聞く・stopまで一連を実行 → jsonlに5種類のeventが並ぶことを確認

Run: `\cat ~/Library/Application\ Support/ccsplit/events/$(date +%Y-%m-%d).jsonl | \cat`
Expected: 5種類のevent行が連続

- [x] Step 6: コミット

メッセージ例: `feat(logger): implement notification, stop, pre_tool_use, user_prompt_submit commands`

---

## フェーズ3: ccsplit.app 最小UI (MVPゴール)

SessionRegistry projection、FSEvents監視、MenuBarExtraクリックで AppleScript focus まで。

### Task 3.1: Event Codable + EventLogReader

Files:
- Create: `ccsplit-app/ccsplit-app/Event.swift`
- Create: `ccsplit-app/ccsplit-app/EventLogReader.swift`
- Create: `ccsplit-app/ccsplit-appTests/EventLogReaderTests.swift`

- [x] Step 1: テスト

```swift
import XCTest
@testable import ccsplit_app

final class EventLogReaderTests: XCTestCase {
    func testParsesSessionStart() throws {
        let line = #"{"ts":"2026-04-16T09:12:34.567Z","event":"session_start","session_id":"abc","terminal_id":"B9BE","cwd":"/tmp","git_branch":"main","claude_pid":123,"claude_start_time":"Wed Apr 16 09:12:34 2026","claude_comm":"claude"}"#
        let ev = try EventLogReader.decode(line: line)
        switch ev.kind {
        case .sessionStart(let s):
            XCTAssertEqual(s.sessionId, "abc")
            XCTAssertEqual(s.terminalId, "B9BE")
            XCTAssertEqual(s.gitBranch, "main")
            XCTAssertEqual(s.claudePid, 123)
        default:
            XCTFail("expected session_start")
        }
    }

    func testParsesStop() throws {
        let line = #"{"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"abc"}"#
        let ev = try EventLogReader.decode(line: line)
        if case .stop(let s) = ev.kind { XCTAssertEqual(s, "abc") } else { XCTFail() }
    }

    func testSkipsBlankLines() throws {
        let content = """
        {"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"a"}

        {"ts":"2026-04-16T09:15:01.000Z","event":"stop","session_id":"b"}
        """
        let events = try EventLogReader.decodeAll(content: content)
        XCTAssertEqual(events.count, 2)
    }

    func testIgnoresCorruptLine() throws {
        let content = """
        {"ts":"2026-04-16T09:15:00.000Z","event":"stop","session_id":"a"}
        this is not json
        {"ts":"2026-04-16T09:15:02.000Z","event":"stop","session_id":"b"}
        """
        let events = try EventLogReader.decodeAll(content: content)
        XCTAssertEqual(events.count, 2)
    }
}
```

- [x] Step 2: Event.swift

```swift
import Foundation

struct Event: Decodable {
    let ts: String
    let kind: Kind

    enum Kind {
        case sessionStart(SessionStart)
        case notification(Notification)
        case stop(String)
        case preToolUse(PreToolUse)
        case userPromptSubmit(String)
    }

    struct SessionStart: Decodable {
        let sessionId: String
        let terminalId: String?
        let cwd: String
        let gitBranch: String?
        let claudePid: UInt32?
        let claudeStartTime: String?
        let claudeComm: String?
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case terminalId = "terminal_id"
            case cwd
            case gitBranch = "git_branch"
            case claudePid = "claude_pid"
            case claudeStartTime = "claude_start_time"
            case claudeComm = "claude_comm"
        }
    }

    struct Notification: Decodable {
        let sessionId: String
        let message: String
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case message
        }
    }

    struct PreToolUse: Decodable {
        let sessionId: String
        let tool: String?
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case tool
        }
    }

    private enum Tag: String, Decodable {
        case sessionStart = "session_start"
        case notification
        case stop
        case preToolUse = "pre_tool_use"
        case userPromptSubmit = "user_prompt_submit"
    }

    private enum CodingKeys: String, CodingKey {
        case ts
        case event
        case session_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ts = try c.decode(String.self, forKey: .ts)
        let tagRaw = try c.decode(String.self, forKey: .event)
        let single = try decoder.singleValueContainer()
        switch tagRaw {
        case "session_start":
            self.kind = .sessionStart(try single.decode(SessionStart.self))
        case "notification":
            self.kind = .notification(try single.decode(Notification.self))
        case "stop":
            let s = try c.decode(String.self, forKey: .session_id)
            self.kind = .stop(s)
        case "pre_tool_use":
            self.kind = .preToolUse(try single.decode(PreToolUse.self))
        case "user_prompt_submit":
            let s = try c.decode(String.self, forKey: .session_id)
            self.kind = .userPromptSubmit(s)
        default:
            throw DecodingError.dataCorruptedError(forKey: .event, in: c, debugDescription: "unknown event: \(tagRaw)")
        }
    }
}
```

- [x] Step 3: EventLogReader.swift

```swift
import Foundation

enum EventLogReader {
    static func decode(line: String) throws -> Event {
        let data = Data(line.utf8)
        return try JSONDecoder().decode(Event.self, from: data)
    }

    static func decodeAll(content: String) throws -> [Event] {
        var out: [Event] = []
        for raw in content.split(whereSeparator: { $0.isNewline }) {
            let s = String(raw).trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if let ev = try? decode(line: s) {
                out.append(ev)
            }
        }
        return out
    }

    static func eventsDir() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ccsplit/events", isDirectory: true)
    }

    static func jsonlFilesSortedAsc() throws -> [URL] {
        let dir = eventsDir()
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
```

- [x] Step 4: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/EventLogReaderTests test`
Expected: 4 tests passed

- [x] Step 5: コミット

メッセージ例: `feat(app): decode jsonl event log lines with event-tagged enum`

### Task 3.2: SessionStatus 状態遷移

Files:
- Create: `ccsplit-app/ccsplit-app/SessionStatus.swift`
- Create: `ccsplit-app/ccsplit-appTests/SessionStatusTests.swift`

- [x] Step 1: テスト

```swift
import XCTest
@testable import ccsplit_app

final class SessionStatusTests: XCTestCase {
    func testStartToRunning() {
        XCTAssertEqual(SessionStatus.transitioned(current: nil, event: .sessionStart), .running)
    }

    func testNotificationSetsWaitingInput() {
        XCTAssertEqual(SessionStatus.transitioned(current: .running, event: .notification), .waitingInput)
    }

    func testPreToolUseMovesWaitingToRunning() {
        XCTAssertEqual(SessionStatus.transitioned(current: .waitingInput, event: .preToolUse), .running)
    }

    func testStopMovesRunningToDone() {
        XCTAssertEqual(SessionStatus.transitioned(current: .running, event: .stop), .done)
    }

    func testUserPromptSubmitResurrectsDone() {
        XCTAssertEqual(SessionStatus.transitioned(current: .done, event: .userPromptSubmit), .running)
    }

    func testStaleResurrectsOnAnyEvent() {
        XCTAssertEqual(SessionStatus.transitioned(current: .stale, event: .notification), .waitingInput)
        XCTAssertEqual(SessionStatus.transitioned(current: .stale, event: .userPromptSubmit), .running)
    }

    func testDeceasedStays() {
        XCTAssertEqual(SessionStatus.transitioned(current: .deceased, event: .notification), .deceased)
    }
}
```

- [x] Step 2: 実装

```swift
import Foundation

enum SessionStatus: String, Equatable {
    case running
    case waitingInput = "waiting_input"
    case done
    case error
    case stale
    case deceased
}

enum EventTransitionKind {
    case sessionStart
    case notification
    case preToolUse
    case stop
    case userPromptSubmit
}

extension SessionStatus {
    static func transitioned(current: SessionStatus?, event: EventTransitionKind) -> SessionStatus {
        if current == .deceased { return .deceased }
        switch (current, event) {
        case (_, .sessionStart): return .running
        case (_, .notification): return .waitingInput
        case (_, .preToolUse): return .running
        case (_, .stop): return .done
        case (_, .userPromptSubmit): return .running
        }
    }
}
```

- [x] Step 3: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/SessionStatusTests test`
Expected: 7 passed

- [x] Step 4: コミット

メッセージ例: `feat(app): implement SessionStatus state transitions`

### Task 3.3: SessionRegistry projection

Files:
- Create: `ccsplit-app/ccsplit-app/SessionRegistry.swift`
- Create: `ccsplit-app/ccsplit-appTests/SessionRegistryTests.swift`

- [x] Step 1: テスト

```swift
import XCTest
@testable import ccsplit_app

final class SessionRegistryTests: XCTestCase {
    private func parse(_ lines: [String]) throws -> [Event] {
        try lines.map { try EventLogReader.decode(line: $0) }
    }

    func testRegistersOneSessionOnStart() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":"main","claude_pid":1,"claude_start_time":"x","claude_comm":"claude"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions.count, 1)
        let s = reg.sessions["s1"]!
        XCTAssertEqual(s.terminalId, "T1")
        XCTAssertEqual(s.gitBranch, "main")
        XCTAssertEqual(s.status, .running)
    }

    func testNotificationMovesToWaitingInput() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"notification","session_id":"s1","message":"Approve bash"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        XCTAssertEqual(reg.sessions["s1"]?.status, .waitingInput)
        XCTAssertEqual(reg.sessions["s1"]?.lastMessage, "Approve bash")
    }

    func testSortedByLastEventDesc() throws {
        let events = try parse([
            #"{"ts":"2026-04-16T09:00:00.000Z","event":"session_start","session_id":"s1","terminal_id":"T1","cwd":"/a","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:01:00.000Z","event":"session_start","session_id":"s2","terminal_id":"T2","cwd":"/b","git_branch":null,"claude_pid":null,"claude_start_time":null,"claude_comm":null}"#,
            #"{"ts":"2026-04-16T09:05:00.000Z","event":"user_prompt_submit","session_id":"s1"}"#
        ])
        var reg = SessionRegistry()
        for e in events { reg.apply(e) }
        let sorted = reg.sortedByLastEventDesc()
        XCTAssertEqual(sorted.map(\.sessionId), ["s1", "s2"])
    }
}
```

- [x] Step 2: 実装

```swift
import Foundation

struct SessionEntry {
    let sessionId: String
    var terminalId: String?
    var cwd: String
    var gitBranch: String?
    var claudePid: UInt32?
    var claudeStartTime: String?
    var claudeComm: String?
    var status: SessionStatus
    var lastEventTs: String
    var lastMessage: String?
    var startedAt: String
}

struct SessionRegistry {
    var sessions: [String: SessionEntry] = [:]

    mutating func apply(_ ev: Event) {
        switch ev.kind {
        case .sessionStart(let s):
            let entry = SessionEntry(
                sessionId: s.sessionId,
                terminalId: s.terminalId,
                cwd: s.cwd,
                gitBranch: s.gitBranch,
                claudePid: s.claudePid,
                claudeStartTime: s.claudeStartTime,
                claudeComm: s.claudeComm,
                status: .running,
                lastEventTs: ev.ts,
                lastMessage: nil,
                startedAt: ev.ts
            )
            sessions[s.sessionId] = entry
        case .notification(let n):
            mutate(n.sessionId) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .notification)
                e.lastEventTs = ev.ts
                e.lastMessage = n.message
            }
        case .stop(let sid):
            mutate(sid) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .stop)
                e.lastEventTs = ev.ts
            }
        case .preToolUse(let p):
            mutate(p.sessionId) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .preToolUse)
                e.lastEventTs = ev.ts
            }
        case .userPromptSubmit(let sid):
            mutate(sid) { e in
                e.status = SessionStatus.transitioned(current: e.status, event: .userPromptSubmit)
                e.lastEventTs = ev.ts
            }
        }
    }

    private mutating func mutate(_ sid: String, _ f: (inout SessionEntry) -> Void) {
        guard var e = sessions[sid] else { return }
        f(&e)
        sessions[sid] = e
    }

    func sortedByLastEventDesc() -> [SessionEntry] {
        sessions.values.sorted { $0.lastEventTs > $1.lastEventTs }
    }
}
```

- [x] Step 3: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/SessionRegistryTests test`
Expected: 3 passed

- [x] Step 4: コミット

メッセージ例: `feat(app): project event stream into SessionRegistry`

### Task 3.4: GhosttyFocus (AppleScript)

Files:
- Create: `ccsplit-app/ccsplit-app/GhosttyFocus.swift`

- [x] Step 1: 実装 (ロジック薄いのでテストスキップ、手動確認)

```swift
import Foundation

enum GhosttyFocus {
    static func focus(terminalId: String) {
        let source = """
        tell application "Ghostty"
            activate
            try
                set theTerm to first terminal of first tab of first window whose id is "\(terminalId)"
                focus theTerm
            end try
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&error)
            if let e = error {
                NSLog("[ccsplit] GhosttyFocus error: \(e)")
            }
        }
    }
}
```

注: AppleScriptで terminal.id をID指定で引く構文はGhosttyのSDEFに依存する。動かない場合は全terminal列挙で一致するものを focus に置き換える:

```applescript
tell application "Ghostty"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                if id of term is "<TID>" then
                    focus term
                    activate
                    return
                end if
            end repeat
        end repeat
    end repeat
end tell
```

- [x] Step 2: 手動確認

事前にpaneを1つ開いておき、その terminal.id を確認 (前フェーズの検証スクリプト再利用):

```swift
// 一時的にメインビューにボタンを置いて focus を発火
Button("Focus T1") { GhosttyFocus.focus(terminalId: "<手元で取った実ID>") }
```

クリックでそのpaneにフォーカスが飛ぶことを確認。

- [x] Step 3: コミット

メッセージ例: `feat(app): focus Ghostty terminal by id via AppleScript`

### Task 3.5: LogTail - FSEvents通知 + 保険ポーリング二段構え

codexレビュー指摘: FSEventsは単一ファイル末尾追従には不向き (coalescing・日次ロール切替で取りこぼし可能性あり)。そのため以下の設計を採る:

- ディレクトリ `events/` を `FSEventStreamCreate` で監視 (新ファイル作成・既存ファイル変更の通知に使う)
- 同時に1秒ごとのTimer (`DispatchSourceTimer`) で「events/内のjsonlサイズをチェックし、既読offsetより増えていたら差分読み出し」をバックアップ
- 既読offsetは `[URL: UInt64]` map で保持、日次ロール時は新ファイルが最初に現れた段階でoffset=0から読む
- FSEvents経由でもポーリング経由でも `readNew(url:)` 呼び出しは共通、内部でoffsetに基づき重複排除

Files:
- Create: `ccsplit-app/ccsplit-app/LogTail.swift`
- Create: `ccsplit-app/ccsplit-appTests/LogTailTests.swift`

- [x] Step 1: テスト - オフセット管理と増分読み出しの純ロジックだけテスト

```swift
import XCTest
@testable import ccsplit_app

final class LogTailTests: XCTestCase {
    func testReadNewReturnsAllLinesFirstTime() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("2026-04-16.jsonl")
        try "line1\nline2\n".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        let lines = reader.readNew(url: f)
        XCTAssertEqual(lines, ["line1", "line2"])
    }

    func testReadNewReturnsOnlyAppendedLines() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("d.jsonl")
        try "line1\n".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        _ = reader.readNew(url: f)
        let handle = try FileHandle(forWritingTo: f)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("line2\nline3\n".utf8))
        try handle.close()
        let lines = reader.readNew(url: f)
        XCTAssertEqual(lines, ["line2", "line3"])
    }

    func testReadNewHandlesPartialLineByReadingAgainNextTime() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("d.jsonl")
        // 書き込み途中で改行なしで切れているケース
        try "lineA\npart".write(to: f, atomically: true, encoding: .utf8)
        let reader = LogTail.Reader()
        let first = reader.readNew(url: f)
        XCTAssertEqual(first, ["lineA"])
        let handle = try FileHandle(forWritingTo: f)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("ial\n".utf8))
        try handle.close()
        let second = reader.readNew(url: f)
        XCTAssertEqual(second, ["partial"])
    }
}
```

- [x] Step 2: 実装

```swift
import Foundation
import CoreServices

enum LogTail {
    final class Reader {
        private var offsets: [String: UInt64] = [:]
        private var carry: [String: String] = [:]

        func reset(url: URL) {
            offsets[url.path] = 0
            carry[url.path] = nil
        }

        func readNew(url: URL) -> [String] {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? handle.close() }
            let start = offsets[url.path] ?? 0
            do { try handle.seek(toOffset: start) } catch { return [] }
            let data: Data
            do { data = try handle.readToEnd() ?? Data() } catch { return [] }
            let newOffset = (try? handle.offset()) ?? start
            offsets[url.path] = newOffset
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }
            let combined = (carry[url.path] ?? "") + text
            let endsWithNewline = combined.hasSuffix("\n")
            var parts = combined.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
            if !endsWithNewline, !parts.isEmpty {
                carry[url.path] = parts.removeLast()
            } else {
                carry[url.path] = nil
            }
            return parts.filter { !$0.isEmpty }
        }
    }

    final class Watcher {
        private var stream: FSEventStreamRef?
        private var timer: DispatchSourceTimer?
        private let onChange: () -> Void
        private let directory: String

        init(directory: String, onChange: @escaping () -> Void) {
            self.directory = directory
            self.onChange = onChange
        }

        func start() {
            startFSEvents()
            startPollingFallback()
        }

        func stop() {
            if let s = stream {
                FSEventStreamStop(s)
                FSEventStreamInvalidate(s)
                stream = nil
            }
            timer?.cancel()
            timer = nil
        }

        private func startFSEvents() {
            var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let cb: FSEventStreamCallback = { _, clientInfo, _, _, _, _ in
                let w = Unmanaged<Watcher>.fromOpaque(clientInfo!).takeUnretainedValue()
                w.onChange()
            }
            stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                cb,
                &ctx,
                [directory] as CFArray,
                UInt64(kFSEventStreamEventIdSinceNow),
                0.05,
                UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            )
            if let s = stream {
                FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
                FSEventStreamStart(s)
            }
        }

        private func startPollingFallback() {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            t.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
            t.setEventHandler { [weak self] in self?.onChange() }
            t.resume()
            timer = t
        }
    }
}
```

設計ポイント:
- `Reader` は `carry` で改行なしの途中行を次回読み出しに回す (logger側のO_APPEND + `\n`終端で基本なくならないが、将来の書き込み中断・非同期タイミングに対する保険)
- `Watcher` の `onChange` は events/ディレクトリに何か動きがあったら呼ばれる。コールバック側 (AppState) が「全jsonlを走査して増分取得」する責務を持つ
- FSEvents latency `0.05` と `kFSEventStreamCreateFlagNoDefer` で「イベント1件目をすぐ通知」するように
- ポーリング `1秒` は保険。FSEventsが抜けても高々1秒で追いつく

- [x] Step 3: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/LogTailTests test`
Expected: 3 tests passed

- [x] Step 4: 手動確認

一時的にccsplit-app内にWatcherをinitして、別paneで `\echo '{}' >> ~/Library/Application\ Support/ccsplit/events/manual.jsonl` を叩き、NSLogに通知が届くことを確認。

- [x] Step 5: コミット

メッセージ例: `feat(app): tail event log directory with FSEvents plus 1s polling fallback`

### Task 3.6: 起動時リプレイ + ライブ追従 + MenuBarView

Files:
- Modify: `ccsplit-app/ccsplit-app/ccsplitApp.swift`
- Create: `ccsplit-app/ccsplit-app/MenuBarView.swift`
- Create: `ccsplit-app/ccsplit-app/AppState.swift`

- [x] Step 1: `AppState.swift`

```swift
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var registry = SessionRegistry()
    private let reader = LogTail.Reader()
    private var watcher: LogTail.Watcher?

    func bootstrap() {
        replayAllJsonl()
        startWatching()
    }

    private func replayAllJsonl() {
        let files = (try? EventLogReader.jsonlFilesSortedAsc()) ?? []
        for f in files {
            let lines = reader.readNew(url: f)
            for line in lines {
                if let ev = try? EventLogReader.decode(line: line) {
                    registry.apply(ev)
                }
            }
        }
    }

    private func startWatching() {
        let dir = EventLogReader.eventsDir().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        watcher = LogTail.Watcher(directory: dir) { [weak self] in
            self?.onFsEvent()
        }
        watcher?.start()
    }

    private func onFsEvent() {
        let files = (try? EventLogReader.jsonlFilesSortedAsc()) ?? []
        var appliedAny = false
        for f in files {
            let lines = reader.readNew(url: f)
            for line in lines {
                if let ev = try? EventLogReader.decode(line: line) {
                    registry.apply(ev)
                    appliedAny = true
                }
            }
        }
        if appliedAny { objectWillChange.send() }
    }
}
```

- [x] Step 2: `MenuBarView.swift`

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.registry.sessions.isEmpty {
                Text("No sessions").foregroundStyle(.secondary)
            } else {
                ForEach(state.registry.sortedByLastEventDesc(), id: \.sessionId) { s in
                    row(s)
                }
            }
            Divider()
            Button("Quit ccsplit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(8)
        .frame(minWidth: 320)
    }

    private func row(_ s: SessionEntry) -> some View {
        Button {
            if let id = s.terminalId { GhosttyFocus.focus(terminalId: id) }
        } label: {
            HStack {
                Circle().fill(color(for: s.status)).frame(width: 10, height: 10)
                Text((s.cwd as NSString).lastPathComponent)
                if let b = s.gitBranch {
                    Text("[\(b)]").foregroundStyle(.secondary)
                }
                Spacer()
                Text(relativeAge(s.lastEventTs)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func color(for s: SessionStatus) -> Color {
        switch s {
        case .running: return .green
        case .waitingInput: return .orange
        case .done: return .gray
        case .error: return .red
        case .stale: return Color.gray.opacity(0.4)
        case .deceased: return Color.gray.opacity(0.2)
        }
    }

    private func relativeAge(_ ts: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = fmt.date(from: ts) else { return "" }
        let s = Int(-d.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m" }
        return "\(s/3600)h"
    }
}
```

- [x] Step 3: `ccsplitApp.swift` を更新

```swift
import SwiftUI

@main
struct CcsplitApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("ccsplit", systemImage: "bubble.left.and.bubble.right") {
            MenuBarView(state: state)
                .task { state.bootstrap() }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [x] Step 4: 統合手動確認 - MVPゴール

1. アプリをビルド&起動: `open $(xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -showBuildSettings -configuration Debug | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/ccsplit-app.app`
2. settings.jsonにccsplit-loggerの5hook登録 (フェーズ2で用意したhooks設定を実行パス経由で)
3. 複数のGhostty paneで `claude` を起動
4. メニューバーアイコンから吹き出しを展開
5. 各セッション行が表示されていること
6. クリックでそのpaneにGhostty内の該当terminalがfocusされること

- [x] Step 5: MVPコミット

メッセージ例: `feat(app): implement MVP menubar with session list and focus integration`

### MVPゲート (ユーザ確認)

MVPが動いた段階でユーザにデモ報告。追加フェーズ進行前に方向性再確認。

---

## フェーズ4: 生存確認

### Task 4.1: LivenessChecker

Files:
- Create: `ccsplit-app/ccsplit-app/LivenessChecker.swift`
- Modify: `ccsplit-app/ccsplit-app/SessionRegistry.swift` (deceased遷移の口)
- Create: `ccsplit-app/ccsplit-appTests/LivenessCheckerTests.swift`

- [x] Step 1: テスト (PID3点チェックの純ロジック部)

```swift
import XCTest
@testable import ccsplit_app

final class LivenessCheckerTests: XCTestCase {
    func testAllMatch() {
        let info = PsInfo(pid: 123, lstart: "Wed Apr 16 09:12:34 2026", comm: "claude")
        let ok = LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info)
        XCTAssertTrue(ok)
    }
    func testStartTimeMismatchFails() {
        let info = PsInfo(pid: 123, lstart: "Thu Apr 17 10:00:00 2026", comm: "claude")
        XCTAssertFalse(LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info))
    }
    func testCommMismatchFails() {
        let info = PsInfo(pid: 123, lstart: "Wed Apr 16 09:12:34 2026", comm: "zsh")
        XCTAssertFalse(LivenessChecker.verify(expected: (123, "Wed Apr 16 09:12:34 2026", "claude"), current: info))
    }
}
```

- [x] Step 2: 実装

```swift
import Foundation

struct PsInfo { let pid: UInt32; let lstart: String; let comm: String }

enum LivenessChecker {
    static func verify(expected: (UInt32, String, String), current: PsInfo) -> Bool {
        current.pid == expected.0 && current.lstart == expected.1 && current.comm == expected.2
    }

    static func queryPs(pid: UInt32) -> PsInfo? {
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments = ["-p", String(pid), "-o", "pid=,lstart=,comm="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // parse (logger側と同じフォーマット)
        let parts = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 7, let pid = UInt32(parts[0]) else { return nil }
        let lstart = parts[1...5].joined(separator: " ")
        let comm = parts[6...].joined(separator: " ")
        return PsInfo(pid: pid, lstart: lstart, comm: comm)
    }

    static func ghosttyTerminalIds() -> Set<String> {
        let source = """
        tell application "Ghostty"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with term in terminals of t
                        set out to out & (id of term) & linefeed
                    end repeat
                end repeat
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let res = script.executeAndReturnError(&err)
        let text = res.stringValue ?? ""
        return Set(text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }
}
```

- [x] Step 3: AppStateに10秒タイマーを追加

```swift
// AppState.swift 抜粋
private var livenessTimer: Timer?

func bootstrap() {
    replayAllJsonl()
    startWatching()
    startLivenessTimer()
}

private func startLivenessTimer() {
    livenessTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.runLivenessCheck() }
    }
}

private func runLivenessCheck() {
    let terms = LivenessChecker.ghosttyTerminalIds()
    for (sid, e) in registry.sessions {
        if [.running, .waitingInput, .done, .stale].contains(e.status) == false { continue }
        if let pid = e.claudePid, let st = e.claudeStartTime, let cm = e.claudeComm {
            if let cur = LivenessChecker.queryPs(pid: pid) {
                if !LivenessChecker.verify(expected: (pid, st, cm), current: cur) {
                    registry.markDeceased(sid: sid, reason: .claudeTerminated)
                    continue
                }
            } else {
                registry.markDeceased(sid: sid, reason: .claudeTerminated)
                continue
            }
        }
        if let tid = e.terminalId, !terms.contains(tid) {
            registry.markDeceased(sid: sid, reason: .paneClosed)
        }
    }
    objectWillChange.send()
}
```

`SessionRegistry` に `markDeceased` / stale判定を追加:

```swift
enum DeceasedReason { case claudeTerminated; case paneClosed; case timeout }

extension SessionRegistry {
    mutating func markDeceased(sid: String, reason: DeceasedReason) {
        mutate(sid) { e in
            e.status = .deceased
            e.deceasedReason = reason
        }
    }

    mutating func applyStaleAfter(_ now: Date) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (sid, e) in sessions {
            guard let d = fmt.date(from: e.lastEventTs) else { continue }
            let age = now.timeIntervalSince(d)
            if e.status == .running || e.status == .waitingInput || e.status == .done {
                if age >= 30 * 60 { mutate(sid) { $0.status = .stale } }
            }
            if e.status == .stale && e.claudePid == nil && age >= 2.5 * 3600 {
                mutate(sid) { $0.status = .deceased; $0.deceasedReason = .timeout }
            }
        }
    }
}
```

`SessionEntry` に `deceasedReason: DeceasedReason?` を足す。

- [x] Step 4: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/LivenessCheckerTests test`
Expected: 3 passed

- [x] Step 5: 手動確認

- `claude` を起動 → `/exit` で終了 → 10秒以内にメニューバーで該当行が deceased (取り消し線) に
- Ghostty paneごと閉じる → 10秒以内に deceased

- [x] Step 6: コミット

メッセージ例: `feat(app): add PID 3-point liveness check with 10s cadence`

---

## フェーズ5: 自動展開・通知バナー・未紐付け選択UI

### Task 5.1: Notification時の自動展開強調

Files:
- Modify: `ccsplit-app/ccsplit-app/MenuBarView.swift`
- Modify: `ccsplit-app/ccsplit-app/AppState.swift`

- [ ] Step 1: `waitingInput` 行をハイライト (背景色橙寄り) + 1行下にメッセージを表示

MenuBarView の `row(_:)` で `if s.status == .waitingInput` 分岐し、`VStack(alignment:.leading)` で2行レイアウト。

```swift
private func row(_ s: SessionEntry) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Circle().fill(color(for: s.status)).frame(width: 10, height: 10)
            Text((s.cwd as NSString).lastPathComponent).fontWeight(s.status == .waitingInput ? .semibold : .regular)
            if let b = s.gitBranch { Text("[\(b)]").foregroundStyle(.secondary) }
            Spacer()
            Text(relativeAge(s.lastEventTs)).foregroundStyle(.secondary)
        }
        if s.status == .waitingInput, let msg = s.lastMessage {
            Text(msg).font(.caption).foregroundStyle(.orange).padding(.leading, 16)
        }
    }
    .padding(4)
    .background(s.status == .waitingInput ? Color.orange.opacity(0.1) : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture {
        if let id = s.terminalId { GhosttyFocus.focus(terminalId: id) }
    }
}
```

- [ ] Step 2: 手動確認

Claude Code内でBashツール等を呼んで承認待ちにし、メニューを開くと該当行がハイライト + message表示されていることを確認。

- [ ] Step 3: コミット

メッセージ例: `feat(app): highlight waiting_input rows with notification message`

### Task 5.2: macOS通知バナー

Files:
- Modify: `ccsplit-app/ccsplit-app/AppState.swift`
- Modify: `ccsplit-app/ccsplit-app/ccsplitApp.swift`

- [ ] Step 1: UserNotifications権限要求とpost

```swift
import UserNotifications

// AppStateの bootstrap末尾で:
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// apply中のNotification時に:
private func postBanner(for entry: SessionEntry) {
    let content = UNMutableNotificationContent()
    content.title = (entry.cwd as NSString).lastPathComponent
    content.body = entry.lastMessage ?? "waiting for input"
    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req)
}
```

`apply(_:)` の notification分岐で `if result.status == .waitingInput { postBanner(for: entry) }` を呼ぶ。

- [ ] Step 2: 手動確認

Claude Code の Notification Hook発火でmacOSバナーが出ること。

- [ ] Step 3: コミット

メッセージ例: `feat(app): post macOS banner on Notification events`

### Task 5.3: 未紐付けセッションの手動選択UIと永続化

codexレビュー指摘: 同一cwd複数pane時は `terminal_id=null` となり後続イベントも再同定情報を持たないため、手動紐付け結果を永続化して ccsplit.app 再起動後にも残す経路を明記する。永続化先は `~/Library/Application Support/ccsplit/manual_pairings.json` で、キー=session_id、値=terminal_id。paneが閉じて terminal が存在しなくなった場合、生存確認周期で対応エントリも削除する。

Files:
- Create: `ccsplit-app/ccsplit-app/ManualPairingsStore.swift`
- Create: `ccsplit-app/ccsplit-appTests/ManualPairingsStoreTests.swift`
- Create: `ccsplit-app/ccsplit-app/ManualPairView.swift`
- Modify: `ccsplit-app/ccsplit-app/MenuBarView.swift`
- Modify: `ccsplit-app/ccsplit-app/AppState.swift` (pairings 読み書きと起動時ロード)
- Modify: `ccsplit-app/ccsplit-app/LivenessChecker.swift` (削除済みterminalのpairingを自動クリーンアップ)

- [ ] Step 1: `ManualPairingsStore` のテスト

```swift
import XCTest
@testable import ccsplit_app

final class ManualPairingsStoreTests: XCTestCase {
    func testSaveAndLoadRoundtrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var store = ManualPairingsStore(fileURL: tmp)
        store.set(sessionId: "s1", terminalId: "T1")
        store.set(sessionId: "s2", terminalId: "T2")
        try store.save()

        var loaded = ManualPairingsStore(fileURL: tmp)
        try loaded.load()
        XCTAssertEqual(loaded.get(sessionId: "s1"), "T1")
        XCTAssertEqual(loaded.get(sessionId: "s2"), "T2")
    }

    func testLoadMissingFileReturnsEmpty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var s = ManualPairingsStore(fileURL: tmp)
        try s.load()
        XCTAssertNil(s.get(sessionId: "x"))
    }

    func testRemoveTerminalCascadesDeletion() {
        var s = ManualPairingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        s.set(sessionId: "s1", terminalId: "T1")
        s.set(sessionId: "s2", terminalId: "T1")
        s.set(sessionId: "s3", terminalId: "T2")
        s.removePairingsReferring(terminalIds: ["T1"])
        XCTAssertNil(s.get(sessionId: "s1"))
        XCTAssertNil(s.get(sessionId: "s2"))
        XCTAssertEqual(s.get(sessionId: "s3"), "T2")
    }
}
```

- [ ] Step 2: `ManualPairingsStore.swift` 実装

```swift
import Foundation

struct ManualPairingsStore {
    private(set) var map: [String: String] = [:]
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { map = [:]; return }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { map = [:]; return }
        map = (try JSONDecoder().decode([String: String].self, from: data))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(map)
        try data.write(to: fileURL, options: .atomic)
    }

    mutating func set(sessionId: String, terminalId: String) {
        map[sessionId] = terminalId
    }

    func get(sessionId: String) -> String? { map[sessionId] }

    mutating func removePairingsReferring(terminalIds: Set<String>) {
        map = map.filter { !terminalIds.contains($0.value) }
    }

    static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ccsplit/manual_pairings.json")
    }
}
```

- [ ] Step 3: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/ManualPairingsStoreTests test`
Expected: 3 passed

- [ ] Step 4: AppStateに pairings の読み書きを組み込む

```swift
// AppState.swift 追加箇所
@Published private(set) var pairings = ManualPairingsStore(fileURL: ManualPairingsStore.defaultURL())

func bootstrap() {
    try? pairings.load()
    replayAllJsonl()
    startWatching()
    startLivenessTimer()
}

func setManualPairing(sessionId: String, terminalId: String) {
    pairings.set(sessionId: sessionId, terminalId: terminalId)
    try? pairings.save()
    objectWillChange.send()
}

func effectiveTerminalId(for entry: SessionEntry) -> String? {
    entry.terminalId ?? pairings.get(sessionId: entry.sessionId)
}
```

- [ ] Step 5: `ManualPairView.swift`

```swift
import SwiftUI

struct ManualPairView: View {
    let sessionId: String
    let cwd: String
    let candidates: [(id: String, cwd: String, name: String)]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("未紐付けセッション (cwd=\(cwd)) を紐付けるpaneを選択").font(.headline).padding(.bottom, 4)
            List(candidates, id: \.id) { c in
                Button {
                    onSelect(c.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.name)
                            Text(c.cwd).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("この pane にfocus") {
                            GhosttyFocus.focus(terminalId: c.id)
                        }.buttonStyle(.borderless)
                    }
                }
            }
            .frame(width: 480, height: 300)
        }
        .padding(8)
    }
}
```

候補取得 `candidates` は `enumerate_terminals` 相当のロジックをswift側にも用意する (AppleScriptで全terminal列挙 → 配列化)。`ccsplit-app/ccsplit-app/GhosttyFocus.swift` に `GhosttyFocus.listTerminals() -> [(id:, cwd:, name:)]` を追加。

- [ ] Step 6: `MenuBarView` の未紐付け行

```swift
// row(_:) の冒頭で分岐
if state.effectiveTerminalId(for: s) == nil {
    Button {
        // popover開く
        state.presentManualPair(for: s)
    } label: {
        HStack {
            Image(systemName: "link.badge.plus")
            Text("未紐付け: \((s.cwd as NSString).lastPathComponent)")
            Spacer()
        }
    }
    .buttonStyle(.plain)
}
```

`AppState` に `@Published var manualPairingSheet: SessionEntry?` を持たせ、sheet modifier で `ManualPairView` を出す。

- [ ] Step 7: LivenessCheckerで無効pairing削除

```swift
// LivenessChecker.swift に追加
static func cleanupPairings(store: inout ManualPairingsStore, liveTerminals: Set<String>) -> Bool {
    let before = store.map
    let stale = Set(before.values).subtracting(liveTerminals)
    if stale.isEmpty { return false }
    store.removePairingsReferring(terminalIds: stale)
    return true
}
```

`AppState.runLivenessCheck()` の末尾で:
```swift
let liveTerms = LivenessChecker.ghosttyTerminalIds()
if LivenessChecker.cleanupPairings(store: &pairings, liveTerminals: liveTerms) {
    try? pairings.save()
}
```

- [ ] Step 8: 手動確認

- 同cwdで2ペイン開き、両方で `claude` 起動 → 両方 `terminal_id=null` で未紐付け行として表示される
- 片方の行の手動紐付けUIから1つpaneを選ぶ → focus飛ぶ
- ccsplit.appを `Quit` して再起動 → 先ほど紐付けたpaneがメニュー行のクリックで再びfocus飛ぶ (永続化が効いている)
- 紐付け先のpaneをGhosttyで閉じる → 10〜20秒以内に `manual_pairings.json` から該当エントリが消え、UIでまた未紐付け行に戻る

- [ ] Step 9: コミット

メッセージ例: `feat(app): persist manual pane pairings and cleanup stale entries`

---

## フェーズ6: ログローテーション・7日保持

### Task 6.1: 8日以上前のjsonl削除

Files:
- Create: `ccsplit-app/ccsplit-app/LogRotator.swift`
- Create: `ccsplit-app/ccsplit-appTests/LogRotatorTests.swift`

- [ ] Step 1: テスト

```swift
import XCTest
@testable import ccsplit_app

final class LogRotatorTests: XCTestCase {
    func testDeletesFilesOlderThan7Days() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let today = Date()
        let old = Calendar.current.date(byAdding: .day, value: -10, to: today)!
        let recent = Calendar.current.date(byAdding: .day, value: -3, to: today)!

        let oldURL = tmp.appendingPathComponent(LogRotator.nameFor(date: old))
        let recentURL = tmp.appendingPathComponent(LogRotator.nameFor(date: recent))
        FileManager.default.createFile(atPath: oldURL.path, contents: Data("".utf8))
        FileManager.default.createFile(atPath: recentURL.path, contents: Data("".utf8))

        LogRotator.rotate(directory: tmp, now: today, retentionDays: 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }
}
```

- [ ] Step 2: 実装

```swift
import Foundation

enum LogRotator {
    static func nameFor(date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        return "\(fmt.string(from: date)).jsonl"
    }

    static func rotate(directory: URL, now: Date, retentionDays: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        for url in items {
            guard url.pathExtension == "jsonl" else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let date = fmt.date(from: stem) else { continue }
            let age = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
            if age > retentionDays {
                try? fm.removeItem(at: url)
            }
        }
    }
}
```

- [ ] Step 3: AppStateで起動時 + 1日1回呼ぶ

```swift
func bootstrap() {
    LogRotator.rotate(directory: EventLogReader.eventsDir(), now: Date(), retentionDays: 7)
    // ...
}
// 1日1回のタイマー
Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
    LogRotator.rotate(directory: EventLogReader.eventsDir(), now: Date(), retentionDays: 7)
}
```

- [ ] Step 4: テスト通過

Run: `xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -only-testing:ccsplit-appTests/LogRotatorTests test`
Expected: 1 passed

- [ ] Step 5: コミット

メッセージ例: `feat(app): rotate event log files past 7 day retention`

---

## フェーズ7: 配布 / Login Item / hooks自動設定

### Task 7.1: 単体ビルド配布スクリプト

Files:
- Create: `scripts/build-release.sh`

- [ ] Step 1: スクリプト作成

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build -p ccsplit-logger --release

xcodebuild \
  -project ccsplit-app/ccsplit-app.xcodeproj \
  -scheme ccsplit-app \
  -configuration Release \
  -derivedDataPath build/xcode \
  build

APP_PATH="build/xcode/Build/Products/Release/ccsplit-app.app"
test -d "$APP_PATH" || { \echo "app bundle not found: $APP_PATH"; exit 1; }

mkdir -p dist
cp target/release/ccsplit-logger dist/ccsplit-logger
rm -rf dist/ccsplit-app.app
cp -R "$APP_PATH" dist/

\echo "logger: dist/ccsplit-logger"
\echo "app bundle: dist/ccsplit-app.app"
```

- [ ] Step 2: 実行して dist/ に logger と .appバンドル が並ぶことを確認

Run: `bash scripts/build-release.sh && ls dist/`
Expected: `ccsplit-app.app ccsplit-logger`

Run: `open dist/ccsplit-app.app`
Expected: メニューバーにアイコンが出る (Dockアイコンなし)

- [ ] Step 3: コミット

メッセージ例: `chore: release build script emitting logger CLI and app bundle`

### Task 7.2: hooks自動設定CLI

Files:
- Create: `ccsplit-logger/src/commands/install.rs`

- [ ] Step 1: `ccsplit-logger install` で `~/.claude/settings.json` に5hookをマージ

設計ドキュメントの `ユーザ側のセットアップ` セクションのJSON片を、既存settings.jsonに非破壊マージする実装を追加 (serde_json::Value でマージ)。

- [ ] Step 2: idempotent確認テスト (一時ファイルで)

- [ ] Step 3: コミット

メッセージ例: `feat(logger): add install subcommand merging hooks into settings.json`

---

## フェーズ8: upstream PR 準備 (別セッション推奨)

設計ドキュメントの "upstream PR (最優先課題)" の2件 (Claude Code SessionEnd hook / Ghostty terminal.surface_id) は、本計画のscopeを外れる (別PRフロー、別リポジトリ)。このフェーズでは以下だけ行う:

### Task 8.1: issue化

- [ ] Claude Code本家へのSessionEnd hook提案内容を `docs/upstream-claude-code-session-end.md` にまとめる
- [ ] Ghostty本家へのsurface_id提案内容を `docs/upstream-ghostty-surface-id.md` にまとめる

ここはPR本体は別途。

---

## Self-Review チェック結果

仕様カバレッジ (ccsplit-design.md との照合):

- ペイン特定アーキテクチャ (cwd + name==Claude Code) → Task 2.7
- イベントログ仕様 (配置、日次ローテ、jsonl) → Task 2.2, 2.3, 6.1
- session_start payload (git_branch, claude_pid 3点) → Task 2.5, 2.6, 2.8
- 保持期間7日、日跨ぎ復元 → Task 3.1 (全jsonl古い順走査), Task 6.1
- 状態遷移マシン → Task 3.2
- 生存確認3点チェック + 時間ベースフォールバック → Task 4.1
- メニューバーUI (並び順、行レイアウト、自動展開) → Task 3.6, 5.1
- 未紐付けUIの永続化付き手動紐付け → Task 5.3 (ManualPairingsStore 永続化 + LivenessCheckerでクリーンアップ)
- 通知バナー → Task 5.2
- hooks設定 → Task 7.2

codexレビュー指摘への対応:

- pane再同定経路 (同cwd複数pane) → Task 5.3 で `manual_pairings.json` 永続化 + LivenessChecker連携、`effectiveTerminalId(for:)` で一元解決
- FSEvents追記検知の信頼性 → Task 3.5 で FSEvents + 1秒ポーリング二段構え、carry buffer で途中行も保持
- `.app` バンドル化 → Task 1.2 を Swift Package からXcode project (.app target、LSUIElement=true) に差し替え
- Ghostty focus の事前検証 → フェーズ0にTask 0.4 (検証C) を追加。id-match・iteration fallback・Space/tab越えの挙動・NSAppleScript同等性を確認
- Hook同期パスの重処理 → Task 2.0 で self-detach 機構 (stdin吸い出し→自己再spawn with env→親 exit) を先に用意。hook由来の5コマンドのみ `needs_detach() == true` でdetach経路を通し、管理系CLI (install, --help等) はフォアグラウンドのまま stdout/stderrを保持
- `comm == "claude"` 固定判定 → Task 2.6 で `is_claude_like(comm, command)` パターンマッチに差し替え、`CLAUDE_PATTERNS` 定数 + `command=` full path のsubstring matchで判定。claude_commはobserved値をそのまま記録、LivenessCheckerは記録値と現在値の一致で判定する (固定文字列依存なし)

プレースホルダスキャン: 完全なコード・コマンド付き。曖昧な "TBD" や "実装する" だけのステップはなし。

型整合性: `SessionEntry.terminalId: String?`、logger側も `terminal_id: Option<String>`。`SessionRegistry.apply(_ ev: Event)` と `EventLogReader.decode(line:)` の返り値型が一致。`AppState.effectiveTerminalId(for:)` は `SessionEntry -> String?` を返し、MenuBarViewのfocus処理とLivenessCheckerクリーンアップで共通して参照される。

---

## 検証結果によるplan差分

フェーズ0検証 A/B/C の結果次第で、以下のTaskの中身が差し替えになる:

- 検証Aで `$PPID != claude本体` と判明 → Task 2.6 に親遡り関数 `find_claude_in_ancestors` を追加し、`session_start.rs` で呼び出す
- 検証Bで name取得が不安定と判明 → Task 2.7 の `find_terminal_id_with_retry` のリトライ回数/間隔を変更 (例: 10回×200ms)
- 検証Cで id-match構文が不通と判明 → Task 3.4 GhosttyFocus を iteration fallback のみにする、もしくは `AXUIElement` (Accessibility API) 経由に差し替え
- 検証Cで totally focus不能 → プロジェクトのコア価値が失われるため、Ghostty upstream PR 待ちの方針に切り替えてMVP範囲縮小をユーザと再協議
- いずれも深刻 → 設計見直しをユーザに諮り、本計画を再改訂

この差分反映は計画の更新で行い、実装開始前にユーザに確認する。
