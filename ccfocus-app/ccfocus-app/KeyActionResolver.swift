import Foundation

enum KeyActionResolver {
    static let maxIndex = 10

    static func numberIndex(forCharacter c: Character) -> Int? {
        switch c {
        case "1": return 0
        case "2": return 1
        case "3": return 2
        case "4": return 3
        case "5": return 4
        case "6": return 5
        case "7": return 6
        case "8": return 7
        case "9": return 8
        case "0": return 9
        default: return nil
        }
    }

    static func select(from entries: [SessionEntry], numberIndex index: Int) -> SessionEntry? {
        guard index >= 0, index < maxIndex, index < entries.count else { return nil }
        return entries[index]
    }
}
