import ApplicationServices
import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)
            HStack {
                Text("Toggle & focus popover:")
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleFocus)
            }
            HStack {
                Text("Cycle to next session:")
                Spacer()
                KeyboardShortcuts.Recorder(for: .cycleNext)
            }
            Divider()
            Text("Accessibility")
                .font(.headline)
            HStack {
                Image(systemName: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isAccessibilityTrusted ? .green : .orange)
                Text(isAccessibilityTrusted
                     ? "Granted — peek can raise Ghostty windows"
                     : "Not granted — peek will not raise Ghostty windows")
                    .font(.caption)
                Spacer()
                if !isAccessibilityTrusted {
                    Button("Open Settings") { promptAndOpenAccessibilitySettings() }
                }
                Button("Re-check") { isAccessibilityTrusted = AXIsProcessTrusted() }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 260, alignment: .topLeading)
    }

    private func promptAndOpenAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
