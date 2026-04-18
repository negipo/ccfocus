import Foundation

struct PsInfo { let pid: UInt32; let lstart: String; let comm: String }

struct ExpectedProcess {
    let pid: UInt32
    let lstart: String
    let comm: String
}

enum LivenessChecker {
    static func verify(expected: ExpectedProcess, current: PsInfo) -> Bool {
        current.pid == expected.pid && current.lstart == expected.lstart && current.comm == expected.comm
    }

    static func queryPs(pid: UInt32) -> PsInfo? {
        let proc = Process()
        proc.launchPath = "/bin/ps"
        proc.arguments = ["-p", String(pid), "-o", "pid=,lstart=,comm="]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = str.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 7, let pid = UInt32(parts[0]) else { return nil }
        let lstart = parts[1...5].joined(separator: " ")
        let comm = parts[6...].joined(separator: " ")
        return PsInfo(pid: pid, lstart: lstart, comm: comm)
    }

    static func cleanupPairings(store: inout ManualPairingsStore, liveTerminals: Set<String>) -> Bool {
        let stale = Set(store.map.values).subtracting(liveTerminals)
        if stale.isEmpty { return false }
        store.removePairingsReferring(terminalIds: stale)
        return true
    }

    static func ghosttyTerminalIds() -> Set<String> {
        let source = """
        tell application "Ghostty"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with term in terminals of t
                        set out to out & (id of term) & linefeed
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
        return Set(text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }
}
