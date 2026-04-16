tell application "Ghostty"
    set out to ""
    repeat with w in windows
        repeat with t in tabs of w
            repeat with term in terminals of t
                try
                    set n to name of term
                on error
                    set n to "(no name)"
                end try
                try
                    set wd to working directory of term
                on error
                    set wd to "(no wd)"
                end try
                try
                    set tid to id of term
                on error
                    set tid to "(no id)"
                end try
                set out to out & "id=" & tid & " | name=" & n & " | wd=" & wd & linefeed
            end repeat
        end repeat
    end repeat
    return out
end tell
