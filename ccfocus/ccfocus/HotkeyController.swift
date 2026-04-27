import Foundation
import KeyboardShortcuts

@MainActor
final class HotkeyController {
    var onToggleFocus: (() -> Void)?
    var onCycleNext: (() -> Void)?

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleFocus) { [weak self] in
            self?.onToggleFocus?()
        }
        KeyboardShortcuts.onKeyDown(for: .cycleNext) { [weak self] in
            self?.onCycleNext?()
        }
    }
}
