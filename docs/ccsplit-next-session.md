# ccsplit 次セッション指示 (計画承認 → 実装開始)

## 現在位置

- レポジトリ: /Users/negipo/src/github.com/negipo/ccsplit
- ブランチ: po/ccsplit-impl-plan (作業中、main ブランチから切った)
- 計画: tmp/doc/ccsplit-impl-plan.md (まだコミットしていない)
- 設計: tmp/doc/ccsplit-design.md (前セッションで確定)
- 関連issue: negipo/ccsplit#1, #2, #3

## 前セッションで何をしたか

1. 設計ドキュメント tmp/doc/ccsplit-design.md を全文読込
2. superpowers:writing-plans スキルで tmp/doc/ccsplit-impl-plan.md を作成
3. reviewing-plan-with-codex スキルで codex レビューを4回実施
  - 1回目: 4点指摘 (terminal_id null フォールバック未設計 / FSEvents単独で末尾追従不可 / Swift Package では .app bundle にならない / Ghostty focus 未検証)
  - 2回目: 2点指摘 (Hook同期パスに重処理 / comm=="claude" 固定)
  - 3回目: 1点指摘 (detach全サブコマンド適用でCLI破壊)
  - 4回目: 致命的破綻なし (通過)
4. 修正内容:
  - フェーズ0 に Task 0.4 (Ghostty focus 検証) 追加
  - Task 1.2 を Xcode project 前提に全面書き換え (Swift Package → .app bundle、LSUIElement=true)
  - Task 3.5 を FSEvents + 1秒ポーリング二段構え + carry buffer に差し替え (名前も LogTail に)
  - Task 5.3 に ManualPairingsStore (manual_pairings.json 永続化) と LivenessChecker 連携を追加
  - Task 2.0 として self-detach 機構を新設 (stdin吸い出し→自己再spawn→親exit、hook 5コマンドのみ detach)
  - Task 2.6 の claude 判定を CLAUDE_PATTERNS + command= full path substring match に変更
  - Task 2.8 を env経由 (CCSPLIT_CLAUDE_PID/START/COMM) でclaude情報継承する形に変更

## 次セッションの最初にやること

1. ユーザに計画をレビューしてもらう
  - 気になる箇所 (とくに Task 0.4 検証C、Task 1.2 Xcode project 手動操作、Task 2.0 self-detach) に対するユーザの見解を聞く
  - difit-review スキルで差分レビューに回すのも選択肢 (po/ccsplit-impl-plan の差分は tmp/doc/ccsplit-impl-plan.md 1ファイルのみ)
2. ユーザ承認が取れたら、計画ファイルをコミット (git-committing スキル)
  - メッセージ例: `docs: draft ccsplit implementation plan with phased verification and self-detach logger`
3. subagent-driven-development スキルを呼び出してフェーズ0 Task 0.1 から実装開始

## 実装開始時の重要な注意点

- 実装スタイルは subagent 一択 (ユーザ指示: ユーザはsubagent以外を選ばない)。確認のみ挟む
- Xcode project 作成 (Task 1.2) はエージェント不可。ユーザに手動依頼が必要
  - GUI 操作: Xcode で macOS App テンプレート、Product Name ccsplit-app、Bundle Identifier com.negipo.ccsplit-app、SwiftUI、Include Tests
  - Info.plist に `Application is agent (UIElement)` = YES を追加してもらう
  - App Sandbox はOFF (AppleScript でGhostty制御するため)
- settings.json の一時書き換えが フェーズ0 Task 0.2 / 0.3 / 0.4、Task 2.8 / 2.9 の実機確認で発生する
  - 必ず事前提示 & 作業後元の状態へ復元する (update-config スキル相当の配慮)
- フェーズ0 検証結果次第で後続タスクが差し替えになる
  - 検証A失敗 → Task 2.6 の find_claude_proc 親遡りの最大depthを増やす or CLAUDE_PATTERNS 拡張
  - 検証B失敗 → Task 2.7 の find_terminal_id_with_retry のリトライ回数/間隔を増やす
  - 検証C失敗 → Task 3.4 GhosttyFocus をAccessibility APIに差し替え、最悪コア価値損失なので設計見直し

## 口頭確認なしで進めて良いこと

- 検証用スクリプト (tmp/verify/) の作成 (環境非破壊)
- 計画ファイルのマイナー修正
- tmp/doc/ 配下の追加ドキュメント作成

## ユーザに必ず確認すべきこと

- 計画の最初の承認 (これが最優先)
- 計画ファイルのコミット可否
- Xcode project 作成手順に入る直前 (フェーズ1 Task 1.2)
- settings.json 書き換えの直前 (各検証タスク、Task 2.8 / 2.9の実機確認)
- フェーズ0 検証結果で想定外だった場合の方針決定
- hooks install CLI (Task 7.2) でユーザのsettings.jsonをマージする直前

## ブランチ運用

- po/ccsplit-impl-plan で作業継続
- ここが肥大化した場合 (フェーズ2以降の実装で数十commit規模になる想定) は、MVP完了 (フェーズ3末) の時点でPR化を検討
- PR 化は creating-pr スキル使用

## 引き継ぎメモ

- 計画は tmp/doc/ccsplit-impl-plan.md 単体に収まっている (長文だが分割していない)
- codex session id 019d93de-2bbe-7112-9fdb-4ced79c72960 (直近4回分のコンテキスト保持)
- フェーズ0 Task 0.1 は tmp/verify/verify_hook.sh と verify_ghostty.applescript の作成から始まる
