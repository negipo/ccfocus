# ccfocus

macOSメニューバー常駐アプリ。複数のClaude Codeセッションを横断追跡し、通知が来たGhostty paneへ瞬時に飛べるようにする。

## アーキテクチャ

- ccfocus-logger (Rust CLI): Claude Code Hooksから呼ばれ、AppleScriptでpaneを特定してjsonlにイベントを追記
- ccfocus (Swift/SwiftUI): メニューバー常駐。FSEventsでログを追尾し、状態復元/UI表示/AppleScript focusを担う
- イベントログ (jsonl): `~/Library/Application Support/ccfocus/events/YYYY-MM-DD.jsonl` に日次ローテーション
- 設計詳細: docs/ccfocus-design.md
- 実装計画: docs/ccfocus-impl-plan.md

## Build & Test

```bash
cargo test -p ccfocus-logger      # Rustテスト
cargo clippy -p ccfocus-logger    # Rustリント
cargo build -p ccfocus-logger     # Rustビルド

xcodegen generate --spec ccfocus/project.yml --project ccfocus/  # xcodeproj生成
xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocus -configuration Debug build  # Swiftビルド
xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test  # Swiftテスト
```

## Development Rules

- PRを作成してmainにマージする。mainへの直接pushは避ける
- ccfocus/ccfocus.xcodeprojはproject.ymlから生成されるため、gitに含めない。Swiftファイルを追加した場合は`xcodegen generate`を再実行する
- コミット前にRustは`cargo test`と`cargo clippy`、Swiftは`xcodebuild test`を実行する
- PreToolUse hookがツール呼び出しをブロックした場合、回避策を試みず、ユーザに報告して指示を待つ
- ドキュメント (README.md等) は英語で記述する

## Manual Verification

ccfocusのUI変更を検証する際:

```bash
pkill -x ccfocus 2>/dev/null
xcodegen generate --spec ccfocus/project.yml --project ccfocus/
xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocus -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/ccfocus-*/Build/Products/Debug/ccfocus.app
```

ccfocus-loggerの手動テスト:

```bash
echo '{"session_id":"test","cwd":"/tmp"}' | CCFOCUS_LOGGER_DETACHED=1 cargo run -p ccfocus-logger -- stop
\cat ~/Library/Application\ Support/ccfocus/events/$(date +%Y-%m-%d).jsonl
```
