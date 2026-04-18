import Foundation
import KeyboardShortcuts

@MainActor
final class HotkeyController {
    var onToggleFocus: (() -> Void)?

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleFocus) { [weak self] in
            self?.onToggleFocus?()
        }
    }
}
