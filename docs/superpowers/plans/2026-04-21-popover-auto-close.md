# Popover auto-close on attention-count drop — Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: attention 対象セッション数が >0 から 0 に落ちた瞬間に popover を自動で閉じる。

Architecture: `SessionRegistry` に attention count を computed で公開し、`AppState` は edge-trigger 用の小さな struct `PopoverAutoCloseGate` を持ち、`onFsEvent` / `runLivenessCheck` のバッチ末尾と bootstrap 初期化時に gate を更新する。edge 成立時に `onClosePopover` コールバックで `AppDelegate` が popover を閉じる。

Tech Stack: Swift 5.9 / SwiftUI / AppKit / XCTest / xcodegen

Spec: `docs/superpowers/specs/2026-04-21-popover-auto-close-design.md`

## File map

- Modify `ccfocus/ccfocus/SessionRegistry.swift`: `attentionCount` computed property を追加
- Modify `ccfocus/ccfocusTests/SessionRegistryTests.swift`: `attentionCount` のテストを追加
- Create `ccfocus/ccfocus/PopoverAutoCloseGate.swift`: edge-trigger 判定用の純粋 struct
- Create `ccfocus/ccfocusTests/PopoverAutoCloseGateTests.swift`: gate の単体テスト
- Modify `ccfocus/ccfocus/AppState.swift`: `onClosePopover` / `gate` / `checkAutoClose` を追加、バッチ末尾と bootstrap で呼ぶ
- Modify `ccfocus/ccfocus/CcfocusApp.swift`: `state.onClosePopover` を `AppDelegate` で配線
- Regenerate `ccfocus/ccfocus.xcodeproj` via xcodegen (new Swift files)

---

## Task 1: SessionRegistry.attentionCount

Files:
- Modify: `ccfocus/ccfocus/SessionRegistry.swift`
- Test: `ccfocus/ccfocusTests/SessionRegistryTests.swift`

- [ ] Step 1.1: Write the failing tests

Append to `ccfocus/ccfocusTests/SessionRegistryTests.swift` before the closing `}`:

```swift
    func testAttentionCountIsZeroForEmptyRegistry() {
        let reg = SessionRegistry()
        XCTAssertEqual(reg.attentionCount, 0)
    }

    func testAttentionCountCountsAttentionStatuses() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"asking","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"asking","has_question":true}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"waiting","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"notification","session_id":"waiting","message":"m"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"done","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"done"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"idle","cwd":"/a"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        XCTAssertEqual(reg.sessions["asking"]?.status, .asking)
        XCTAssertEqual(reg.sessions["waiting"]?.status, .waitingInput)
        XCTAssertEqual(reg.sessions["done"]?.status, .done)
        XCTAssertEqual(reg.sessions["idle"]?.status, .idle)
        XCTAssertEqual(reg.attentionCount, 4)
    }

    func testAttentionCountExcludesNonAttentionStatuses() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"run","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"user_prompt_submit","session_id":"run"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"stale","cwd":"/a"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        let now = ISO8601DateFormatter().date(from: "2026-04-20T00:31:00Z")!
        reg.applyStaleAfter(now)
        reg.markDeceased(sid: "run", reason: .claudeTerminated)
        XCTAssertEqual(reg.sessions["run"]?.status, .deceased)
        XCTAssertEqual(reg.sessions["stale"]?.status, .stale)
        XCTAssertEqual(reg.attentionCount, 0)
    }

    func testAttentionCountMixedCount() throws {
        var reg = SessionRegistry()
        let lines = [
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"a","cwd":"/a"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"stop","session_id":"a","has_question":true}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"session_start","session_id":"b","cwd":"/b"}"#,
            #"{"ts":"2026-04-20T00:00:00.000Z","event":"user_prompt_submit","session_id":"b"}"#
        ]
        for line in lines { reg.apply(try EventLogReader.decode(line: line)) }
        XCTAssertEqual(reg.attentionCount, 1)
    }
```

- [ ] Step 1.2: Run tests to verify they fail

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test -only-testing:ccfocusTests/SessionRegistryTests 2>&1 | tail -40`

Expected: 4 failures complaining about missing `attentionCount`.

- [ ] Step 1.3: Implement the computed property

Edit `ccfocus/ccfocus/SessionRegistry.swift`. Inside the existing `extension SessionRegistry { ... }` block (the one with `markDeceased` / `applyStaleAfter`), add this computed property at the top of the extension:

```swift
    var attentionCount: Int {
        sessions.values.reduce(into: 0) { count, entry in
            switch entry.status {
            case .asking, .waitingInput, .done, .idle, .error:
                count += 1
            case .running, .stale, .deceased:
                break
            }
        }
    }
```

- [ ] Step 1.4: Run tests to verify they pass

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test -only-testing:ccfocusTests/SessionRegistryTests 2>&1 | tail -20`

Expected: all `SessionRegistryTests` pass.

- [ ] Step 1.5: Commit

```bash
git add ccfocus/ccfocus/SessionRegistry.swift ccfocus/ccfocusTests/SessionRegistryTests.swift
git commit -m "feat: add SessionRegistry.attentionCount"
```

---

## Task 2: PopoverAutoCloseGate

Files:
- Create: `ccfocus/ccfocus/PopoverAutoCloseGate.swift`
- Test: `ccfocus/ccfocusTests/PopoverAutoCloseGateTests.swift`

- [ ] Step 2.1: Write the failing tests

Create `ccfocus/ccfocusTests/PopoverAutoCloseGateTests.swift`:

```swift
import XCTest
@testable import ccfocus

final class PopoverAutoCloseGateTests: XCTestCase {
    func testInitiallyDoesNotFire() {
        var gate = PopoverAutoCloseGate()
        XCTAssertFalse(gate.apply(current: 0))
    }

    func testFiresWhenDroppingFromPositiveToZero() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 2)
        XCTAssertTrue(gate.apply(current: 0))
    }

    func testDoesNotFireWhenStayingPositive() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 2)
        XCTAssertFalse(gate.apply(current: 1))
    }

    func testDoesNotFireWhenAlreadyZero() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 0)
        XCTAssertFalse(gate.apply(current: 0))
    }

    func testFiresOnEachDropAfterRebound() {
        var gate = PopoverAutoCloseGate()
        _ = gate.apply(current: 1)
        XCTAssertTrue(gate.apply(current: 0))
        _ = gate.apply(current: 1)
        XCTAssertTrue(gate.apply(current: 0))
    }

    func testSyncSetsBaselineSoUnchangedCountDoesNotFire() {
        var gate = PopoverAutoCloseGate()
        gate.sync(to: 3)
        XCTAssertFalse(gate.apply(current: 3))
    }

    func testSyncBaselineStillDetectsDropToZero() {
        var gate = PopoverAutoCloseGate()
        gate.sync(to: 3)
        XCTAssertTrue(gate.apply(current: 0))
    }
}
```

- [ ] Step 2.2: Run tests to verify they fail

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test -only-testing:ccfocusTests/PopoverAutoCloseGateTests 2>&1 | tail -40`

Expected: build failure — `PopoverAutoCloseGate` not defined.

- [ ] Step 2.3: Implement the gate

Create `ccfocus/ccfocus/PopoverAutoCloseGate.swift`:

```swift
import Foundation

struct PopoverAutoCloseGate {
    private var previous: Int = 0

    mutating func apply(current: Int) -> Bool {
        defer { previous = current }
        return previous > 0 && current == 0
    }

    mutating func sync(to count: Int) {
        previous = count
    }
}
```

- [ ] Step 2.4: Regenerate xcodeproj so the new files are included

Run:
```bash
xcodegen generate --spec ccfocus/project.yml --project ccfocus/
```

Expected: Regenerates `ccfocus/ccfocus.xcodeproj` with new Swift files included.

- [ ] Step 2.5: Run tests to verify they pass

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test -only-testing:ccfocusTests/PopoverAutoCloseGateTests 2>&1 | tail -20`

Expected: 7 tests pass.

- [ ] Step 2.6: Commit

```bash
git add ccfocus/ccfocus/PopoverAutoCloseGate.swift ccfocus/ccfocusTests/PopoverAutoCloseGateTests.swift
git commit -m "feat: add PopoverAutoCloseGate for edge-triggered close"
```

---

## Task 3: Wire AppState to emit onClosePopover

Files:
- Modify: `ccfocus/ccfocus/AppState.swift`

- [ ] Step 3.1: Add `onClosePopover` callback

Edit `ccfocus/ccfocus/AppState.swift`. Locate the line:

```swift
    var onOpenPopover: (() -> Void)?
```

and add the new callback just below:

```swift
    var onOpenPopover: (() -> Void)?
    var onClosePopover: (() -> Void)?
```

- [ ] Step 3.2: Add the gate as a private property

Just below `private var bootstrapDone = false`, add:

```swift
    private var autoCloseGate = PopoverAutoCloseGate()
```

- [ ] Step 3.3: Add the `checkAutoClose` method

Immediately below `private func onFsEvent() { ... }` (but outside it), add:

```swift
    private func checkAutoClose() {
        if autoCloseGate.apply(current: registry.attentionCount) {
            onClosePopover?()
        }
    }
```

- [ ] Step 3.4: Sync the gate at the end of `bootstrap` after replay

Edit `bootstrap()`:

```swift
    func bootstrap() {
        LogRotator.rotate(directory: EventLogReader.eventsDir(), now: Date(), retentionDays: 7)
        try? pairings.load()
        replayAllJsonl()
        autoCloseGate.sync(to: registry.attentionCount)
        startWatching()
        runLivenessCheck()
        startLivenessTimer()
        startRotationTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.bootstrapDone = true
        }
    }
```

Note: `runLivenessCheck()` inside `bootstrap` will invoke `checkAutoClose` at its end. Liveness may change `attentionCount` (e.g., marking sessions deceased), so the gate could in principle fire. At this point the popover is not yet shown, so `AppDelegate`'s `isShown` guard makes any fire a no-op. The important guarantee is only that replay itself (pre-liveness) does not fire, and `sync(to:)` provides that.

- [ ] Step 3.5: Call `checkAutoClose` at the end of `onFsEvent` batch

Edit `onFsEvent()`. Its current end is:

```swift
        if appliedAny { objectWillChange.send() }
    }
```

Change to:

```swift
        if appliedAny {
            objectWillChange.send()
            checkAutoClose()
        }
    }
```

- [ ] Step 3.6: Call `checkAutoClose` at the end of `runLivenessCheck`

Edit `runLivenessCheck()`. Its current end is:

```swift
        registry.applyStaleAfter(Date())
        if LivenessChecker.cleanupPairings(store: &pairings, liveTerminals: terms) {
            try? pairings.save()
        }
        objectWillChange.send()
    }
```

Change to:

```swift
        registry.applyStaleAfter(Date())
        if LivenessChecker.cleanupPairings(store: &pairings, liveTerminals: terms) {
            try? pairings.save()
        }
        objectWillChange.send()
        checkAutoClose()
    }
```

- [ ] Step 3.7: Build to verify compile

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocus -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] Step 3.8: Commit

```bash
git add ccfocus/ccfocus/AppState.swift
git commit -m "feat: emit onClosePopover when attention count drops to zero"
```

---

## Task 4: Wire AppDelegate to close the popover

Files:
- Modify: `ccfocus/ccfocus/CcfocusApp.swift`

- [ ] Step 4.1: Wire the callback

Edit `ccfocus/ccfocus/CcfocusApp.swift`. Locate:

```swift
        state.onOpenPopover = { [weak self] in self?.showPopoverUnfocused() }
```

and add the close callback directly below:

```swift
        state.onOpenPopover = { [weak self] in self?.showPopoverUnfocused() }
        state.onClosePopover = { [weak self] in
            guard let self else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
```

- [ ] Step 4.2: Build to verify compile

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocus -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] Step 4.3: Run full test suite

Run: `xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test 2>&1 | tail -20`

Expected: all tests pass.

- [ ] Step 4.4: Commit

```bash
git add ccfocus/ccfocus/CcfocusApp.swift
git commit -m "feat: close popover when AppState signals attention cleared"
```

---

## Task 5: Manual verification

Files: none (runtime verification only)

- [ ] Step 5.1: Rebuild the app bundle

```bash
pkill -x ccfocus 2>/dev/null
xcodegen generate --spec ccfocus/project.yml --project ccfocus/
xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocus -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] Step 5.2: Launch the Debug build

```bash
ls ~/Library/Developer/Xcode/DerivedData/ | rg ccfocus
open ~/Library/Developer/Xcode/DerivedData/ccfocus-<hash>/Build/Products/Debug/ccfocus.app
```

Replace `<hash>` with the actual derived-data hash from the `ls` output.

Expected: the ccfocus menu bar icon appears.

- [ ] Step 5.3: Single-session scenario — auto-close on resolve

1. Start a Claude Code session in Ghostty and let it enter `asking` or `waitingInput` (e.g., trigger a permission prompt).
2. Confirm the popover auto-opens.
3. Click the session row to focus Ghostty and submit a reply so the session transitions to `running` (green).
4. Expected: the popover closes automatically within the next FSEvent tick.

- [ ] Step 5.4: Multi-session scenario — close only on last drop

1. Make two sessions reach `asking`/`waitingInput` simultaneously.
2. Resolve session A → `running`. Expected: popover stays open (attention count is still 1).
3. Resolve session B → `running`. Expected: popover closes automatically.

- [ ] Step 5.5: Manual-open no-op scenario

1. With no attention-worthy sessions (all `running` / `stale` / `deceased`), click the menu bar icon to open the popover manually.
2. Expected: popover stays open; does not auto-close just because attention count is 0. (Edge-trigger requires a >0 → 0 transition.)

- [ ] Step 5.6: Document results in the PR description later; no commit for this task.

---

## Self-review checklist (for plan author)

- Spec coverage
  - Attention set `{asking, waitingInput, done, idle, error}` / non-attention `{running, stale, deceased}` → Task 1 tests + production code
  - Edge-trigger `previous > 0 && current == 0` → Task 2
  - Per-batch wiring in `onFsEvent` / `runLivenessCheck` → Task 3 Steps 3.5 / 3.6
  - Bootstrap sync without firing → Task 3 Step 3.4
  - AppDelegate `performClose` guarded by `isShown` → Task 4 Step 4.1
  - README unchanged (spec says not required) → no task needed
- No placeholders in this plan.
- Type consistency: `PopoverAutoCloseGate`, `apply(current:)`, `sync(to:)`, `attentionCount`, `onClosePopover` — all names are used consistently across tasks.
