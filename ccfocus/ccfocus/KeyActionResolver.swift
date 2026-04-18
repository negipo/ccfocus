import Foundation

enum KeyActionResolver {
    static let maxIndex = 10

    private static let digitToIndex: [Character: Int] = [
        "1": 0, "2": 1, "3": 2, "4": 3, "5": 4,
        "6": 5, "7": 6, "8": 7, "9": 8, "0": 9
    ]

    static func numberIndex(forCharacter character: Character) -> Int? {
        digitToIndex[character]
    }

    static func select(from entries: [SessionEntry], numberIndex index: Int) -> SessionEntry? {
        guard index >= 0, index < maxIndex, index < entries.count else { return nil }
        return entries[index]
    }
}
