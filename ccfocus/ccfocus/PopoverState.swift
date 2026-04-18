import Foundation

enum PopoverState {
    case closed
    case openUnfocused
    case openFocused
}

enum HotkeyAction {
    case showAndFocus
    case focus
    case close
}

struct PopoverStateMachine {
    private(set) var state: PopoverState = .closed

    mutating func handleHotkey() -> HotkeyAction {
        switch state {
        case .closed:
            return .showAndFocus
        case .openUnfocused:
            return .focus
        case .openFocused:
            return .close
        }
    }

    mutating func markOpenedUnfocused() {
        state = .openUnfocused
    }

    mutating func markOpenedFocused() {
        state = .openFocused
    }

    mutating func markBecameKey() {
        if state != .closed {
            state = .openFocused
        }
    }

    mutating func markResignedKey() {
        if state == .openFocused {
            state = .openUnfocused
        }
    }

    mutating func markDidClose() {
        state = .closed
    }
}
