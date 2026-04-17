import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleFocus = Self(
        "toggleFocus",
        default: .init(.f, modifiers: [.command, .option])
    )
}
