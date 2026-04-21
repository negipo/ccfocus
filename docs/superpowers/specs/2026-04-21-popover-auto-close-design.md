# Popover auto-close on attention-count drop

## 背景

現状、ccfocus の popover は以下の場合に自動で開く。

- `notification` イベントでセッションが `waitingInput` になった
- `stop` イベントでセッションが `done` または `asking` になった

一方、自動で閉じる経路は存在しない。ユーザは Esc / 外クリック / 行クリック (Ghostty focus) / ステータスアイコン再クリックで明示的に閉じる必要がある。

要対応のセッションが全部片付いた瞬間に popover が残り続けるのは冗長なので、その瞬間に自動で閉じたい。

## 仕様

### 用語

- 注意対象 (attention) セッション: status が次のいずれか
  - `asking`
  - `waitingInput`
  - `done`
  - `idle`
  - `error`
- 非注意 セッション: status が `running` / `stale` / `deceased` のいずれか

### 発火条件

registry を変更する各経路の末尾で 1 回だけ判定する (per-batch スナップショット)。各 event の apply / 各セッションの mark ごとに都度判定する形にはしない。これにより、1 回の FSEvent で複数行が一気に流れ込む場合や、liveness で複数セッションを順に deceased/stale に落とす場合でも、揺らぎの途中で発火することなく、最終状態で 1 度だけ判定される。

判定で次の両方を満たしたら popover を閉じる。

- 直前の attention count > 0
- 現在の attention count == 0

edge-trigger とし、level では発火しない。すなわち popover を手動で開いた時点で既に attention count が 0 だった場合は閉じない。

### 適用範囲

popover の開き方 (自動 / 手動) を問わず、上記条件を満たせば閉じる。

### 閉じるトリガの由来

理由は問わない。ユーザが Ghostty に戻って prompt を返した結果の running 遷移のみならず、プロセス終了による deceased 遷移、30 分経過による stale 遷移でも閉じる。

## 設計

### `SessionRegistry`

computed プロパティ `attentionCount: Int` を追加する。

```swift
var attentionCount: Int {
    sessions.values.filter { entry in
        switch entry.status {
        case .asking, .waitingInput, .done, .idle, .error:
            return true
        case .running, .stale, .deceased:
            return false
        }
    }.count
}
```

### `AppState`

以下を追加する。

- `var onClosePopover: (() -> Void)?`
- `private var previousAttentionCount: Int = 0`
- `private func checkAutoClose()`

`checkAutoClose` は次を行う。

1. `current = registry.attentionCount` を取得
2. `previousAttentionCount > 0 && current == 0` なら `onClosePopover?()` を呼ぶ
3. `previousAttentionCount = current` で更新

呼び出し箇所は registry を変更する各経路の末尾で 1 回のみ。ループの中 (行単位 / セッション単位) では呼ばない。

- `onFsEvent`: ファイル/行の二重ループを抜けた直後 (全イベント適用後) に 1 回
- `runLivenessCheck`: セッション走査と `applyStaleAfter` を終えた直後に 1 回
- `bootstrap` の `replayAllJsonl` 直後: `checkAutoClose` は呼ばず、`previousAttentionCount = registry.attentionCount` で初期値を同期するだけ (この時点で popover は開いていないので発火させる意味がない)

### `AppDelegate`

`applicationDidFinishLaunching` で次を追加。

```swift
state.onClosePopover = { [weak self] in
    guard let self else { return }
    if self.popover.isShown {
        self.popover.performClose(nil)
    }
}
```

既存の `state.onOpenPopover` 設定の直後に追加する。

## データフロー

1. Claude Code hook 由来のイベント or liveness タイマー発火
2. `AppState` が registry の更新を 0 回以上実行 (1 バッチ)
3. バッチ末尾で `checkAutoClose()` を 1 回呼び出し
4. `previousAttentionCount > 0 && current == 0` なら `onClosePopover?()`
5. `AppDelegate` が `popover.isShown` なら `performClose`

## エッジケース

- popover が閉じている間に attention count が 0 に落ちた → `isShown` チェックで no-op
- attention count が 0 → 正 → 0 と短時間に揺れた → 最後の 0 遷移で 1 回閉じる (冪等)
- `clearMessage` / `clearDoneNotified`: 行クリック時に呼ばれるが status を変えないので attention count は不変。この経路では `onDismiss` が既に popover を閉じるため auto-close の発火も不要
- `error` status: 現状 `SessionStatus.transitioned` で生成経路がないため実際にはカウントに寄与しないが、enum 網羅のため attention 側に含める

## テスト

- `SessionRegistryTests` に `attentionCount` のテストを追加
  - 空 registry は 0
  - 各 status が attention 側 / 非 attention 側で期待通りの寄与をする
  - 複数セッション混在時に合計が正しい
- AppState の edge-trigger は `previousAttentionCount` を内部にテストフックを置くか、純粋ロジックを小さなヘルパー関数に切り出して単体でテストする
- 手動検証
  - 1 セッション `asking` 状態で popover 自動 open
  - 該当行をクリック → Ghostty に focus → prompt 返信 → 当該セッション `running`
  - popover が閉じることを確認
  - 2 セッション `asking` なら 1 件だけ running にした時点では閉じず、2 件目も running にした瞬間に閉じる
  - 手動 open (ステータスアイコンクリック) 時点で attention が 0 なら何が起きても即閉じしない

## 影響範囲

- `SessionRegistry` / `SessionRegistryTests`
- `AppState`
- `AppDelegate`
- README.md の `Session states` テーブルには state / color / label / 遷移 / タイムアウトいずれも触れないため、更新不要
