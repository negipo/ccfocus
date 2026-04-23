# Auto-close respects open source

## 背景

ccfocus のパネルは `registry.attentionCount` が `>0 → 0` に遷移したとき自動で閉じる (`PopoverAutoCloseGate` → `onClosePopover` → `closePanel(reason: .attentionCleared)`)。

現状はこの自動クローズが「パネルをどう開いたか」に関係なく発火する。ユーザがステータスバークリックやグローバルホットキーで能動的に開いたパネルでも、attention が 0 になった瞬間に閉じられてしまう。ユーザが TAB サイクル中などに意図せずパネルが消える不具合相当の挙動。

## 要件

- 自動オープン (新しい attention イベントによるオープン) 起源のパネルに限り、`attentionCleared` での自動クローズを許可する。
- ユーザ操作で開いた、あるいはユーザが事後的に触ったパネルは `attentionCleared` では閉じない。
- 既存の peek 中は閉じないガード (`isPeekActive`) は維持する。
- 既存のその他クローズ経路 (Escape/ホットキー/クリックアウト/コミット/ステータスバートグル) の挙動は変えない。

## 設計

### 状態

`AppDelegate` にフラグ `panelUserOwned: Bool` を追加する。

- 初期値
  - 自動オープン経路 (`state.onOpenPopover` → `showPanelUnfocused`): `false`
  - ステータスバークリック (`togglePopover`) / グローバルホットキー (`handleHotkey` で不可視からのオープン): `true`
- 昇格
  - パネルの `didBecomeKeyNotification` 発火時に `true` に設定する。これにより自動オープン後にユーザがホットキーやクリックで key window 化した場合に user-owned へ昇格する。
- 降格
  - しない。`resignedKey` では降格しない (一度ユーザが触ったパネルは、非フォーカスになっても user-owned のまま扱う)。
- リセット
  - `closePanel` が実際に close を実行したタイミングで `false` に戻す。

### 判定

`PanelCloseDecision.decide` に `panelUserOwned: Bool` 引数を追加する。

- `reason == .attentionCleared && panelUserOwned` のケースを最上部のガードに追加 (既存の peek ガードと同じ構造)。`shouldClose: false` を返す。
- それ以外の挙動は不変。

```swift
static func decide(
    reason: PanelCloseReason,
    isPeekActive: Bool,
    isCcfocusFrontmost: Bool,
    panelUserOwned: Bool
) -> PanelCloseDecision {
    if reason == .attentionCleared && panelUserOwned {
        return PanelCloseDecision(shouldClose: false, shouldCommit: false, shouldRestoreFrontmost: false)
    }
    if reason == .attentionCleared && isPeekActive {
        return PanelCloseDecision(shouldClose: false, shouldCommit: false, shouldRestoreFrontmost: false)
    }
    // 以降は既存ロジック
}
```

### 開閉経路への組み込み

`showPanelUnfocused(automatic: Bool)` として明示引数化し、内部で `panelUserOwned = !automatic` を設定する。

- 呼び出し側
  - `state.onOpenPopover`: `showPanelUnfocused(automatic: true)`
  - `togglePopover` (不可視からのオープン): `showPanelUnfocused(automatic: false)`
  - `handleHotkey` (不可視からのオープン): `showPanelUnfocused(automatic: false)`
- 昇格
  - `didBecomeKeyNotification` observer で `panelUserOwned = true` を設定する (既に `true` でも冪等)
- リセット
  - `closePanel` の `decision.shouldClose` が真で `panel.close()` を実行した直後に `panelUserOwned = false`

## テスト

`PanelCloseDecisionTests` を更新・追加する。

- 追加: `attentionCleared + panelUserOwned=true + peek なし` → `shouldClose=false`
- 追加: `attentionCleared + panelUserOwned=false + peek なし` → `shouldClose=true`
- 追加: `attentionCleared + panelUserOwned=true + peek あり` → `shouldClose=false` (どちらのガードでも閉じない)
- 既存の全ケースに `panelUserOwned: false` を明示的に渡す形で引数を更新する。

`PopoverAutoCloseGate` は責務を変えないので変更しない。

## スコープ外

- 手動オープン中に attention が発生 → 既に `panel.isVisible` ガードで no-op、フラグも変化しない。挙動は従来どおり。
- 自動オープン→自動クローズ後、続けて別の attention が発生したケース: 新しいオープンから再スタート。
- `PopoverAutoCloseGate` の内部挙動。

## 影響範囲

- `ccfocus/ccfocus/PanelCloseDecision.swift`
- `ccfocus/ccfocus/CcfocusApp.swift`
- `ccfocus/ccfocusTests/PanelCloseDecisionTests.swift`
