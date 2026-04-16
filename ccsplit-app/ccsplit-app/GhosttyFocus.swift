import Foundation

enum GhosttyFocus {
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
