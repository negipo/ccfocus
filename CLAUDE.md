# ccsplit

macOSメニューバー常駐アプリ。複数のClaude Codeセッションを横断追跡し、通知が来たGhostty paneへ瞬時に飛べるようにする。

## アーキテクチャ

- ccsplit-logger (Rust CLI): Claude Code Hooksから呼ばれ、AppleScriptでpaneを特定してjsonlにイベントを追記
- ccsplit-app (Swift/SwiftUI): メニューバー常駐。FSEventsでログを追尾し、状態復元/UI表示/AppleScript focusを担う
- イベントログ (jsonl): `~/Library/Application Support/ccsplit/events/YYYY-MM-DD.jsonl` に日次ローテーション
- 設計詳細: docs/ccsplit-design.md
- 実装計画: docs/ccsplit-impl-plan.md

## Build & Test

```bash
cargo test -p ccsplit-logger      # Rustテスト
cargo clippy -p ccsplit-logger    # Rustリント
cargo build -p ccsplit-logger     # Rustビルド

xcodegen generate --spec ccsplit-app/project.yml --project ccsplit-app/  # xcodeproj生成
xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -configuration Debug build  # Swiftビルド
xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-appTests -configuration Debug test  # Swiftテスト
```

## Development Rules

- PRを作成してmainにマージする。mainへの直接pushは避ける
- ccsplit-app/ccsplit-app.xcodeprojはproject.ymlから生成されるため、gitに含めない。Swiftファイルを追加した場合は`xcodegen generate`を再実行する
- コミット前にRustは`cargo test`と`cargo clippy`、Swiftは`xcodebuild test`を実行する
- PreToolUse hookがツール呼び出しをブロックした場合、回避策を試みず、ユーザに報告して指示を待つ

## Manual Verification

ccsplit-appのUI変更を検証する際:

```bash
pkill -x ccsplit-app 2>/dev/null
xcodegen generate --spec ccsplit-app/project.yml --project ccsplit-app/
xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-app -configuration Debug build 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/ccsplit-app-*/Build/Products/Debug/ccsplit-app.app
```

ccsplit-loggerの手動テスト:

```bash
echo '{"session_id":"test","cwd":"/tmp"}' | CCSPLIT_LOGGER_DETACHED=1 cargo run -p ccsplit-logger -- stop
\cat ~/Library/Application\ Support/ccsplit/events/$(date +%Y-%m-%d).jsonl
```
