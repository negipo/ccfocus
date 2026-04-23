import Foundation

enum BranchTextTruncator {
    static let defaultTotal = 20
    static let ellipsis = ".."

    static func truncate(_ value: String, total: Int = defaultTotal) -> String {
        guard total > ellipsis.count else { return value }
        guard value.count > total else { return value }
        let keep = total - ellipsis.count
        let headLen = keep - keep / 2
        let tailLen = keep / 2
        let head = value.prefix(headLen)
        let tail = value.suffix(tailLen)
        return "\(head)\(ellipsis)\(tail)"
    }
}
