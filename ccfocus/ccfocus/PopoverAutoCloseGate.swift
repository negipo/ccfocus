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
