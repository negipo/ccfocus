import Foundation

struct GhosttyTerminalInfo: Identifiable {
    let id: String
    let name: String
    var cwd: String { name }
}

enum GhosttyFocus {
    static func listTerminals() -> [GhosttyTerminalInfo] {
        let source = """
        tell application "Ghostty"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with term in terminals of t
                        set out to out & (id of term) & tab & (name of w) & linefeed
                    end repeat
                end repeat
            end repeat
            return out
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return GhosttyTerminalInfo(id: parts[0], name: parts[1])
        }
    }

    static func focus(terminalId: String) {
        let source = """
        tell application "Ghostty"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with term in terminals of t
                        if (id of term) is "\(terminalId)" then
                            focus term
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        try? proc.run()
    }
}
