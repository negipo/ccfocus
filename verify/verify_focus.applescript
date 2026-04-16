on run argv
    set targetId to item 1 of argv
    tell application "Ghostty"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with term in terminals of t
                    if (id of term) is targetId then
                        focus term
                        return "focused: " & name of term
                    end if
                end repeat
            end repeat
        end repeat
        return "NOT FOUND: " & targetId
    end tell
end run
