import Foundation

enum LogRotator {
    static func nameFor(date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        return "\(fmt.string(from: date)).jsonl"
    }

    static func rotate(directory: URL, now: Date, retentionDays: Int) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        for url in items {
            guard url.pathExtension == "jsonl" else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let date = fmt.date(from: stem) else { continue }
            let age = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
            if age > retentionDays {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
