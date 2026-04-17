import Foundation

let args = CommandLine.arguments
guard args.count == 2 else { fputs("usage: verify_focus_swift.swift <terminal_id>\n", stderr); exit(2) }
let tid = args[1]
let source = """
tell application "Ghostty"
    set tid to "\(tid)"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                if (id of term) is tid then
                    focus term
                    return "focused"
                end if
            end repeat
        end repeat
    end repeat
    return "NOT FOUND"
end tell
"""
var err: NSDictionary?
guard let script = NSAppleScript(source: source) else { print("script init failed"); exit(3) }
let res = script.executeAndReturnError(&err)
if let e = err { print("error: \(e)") } else { print(res.stringValue ?? "ok") }
