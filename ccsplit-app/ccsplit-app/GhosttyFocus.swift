import Foundation

struct GhosttyTerminalInfo: Identifiable {
    let id: String
    let name: String
    let wd: String
}

enum GhosttyFocus {
    static func listTerminals() -> [GhosttyTerminalInfo] {
        let source = """
        tell application "Ghostty"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with term in terminals of t
                        try
                            set n to name of term
                        on error
                            set n to ""
                        end try
                        try
                            set wd to working directory of term
                        on error
                            set wd to ""
                        end try
                        try
                            set tid to id of term
                        on error
                            set tid to ""
                        end try
                        set out to out & tid & tab & n & tab & wd & linefeed
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
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            return GhosttyTerminalInfo(id: parts[0], name: parts[1], wd: parts[2])
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
