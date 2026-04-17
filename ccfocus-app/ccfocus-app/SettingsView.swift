import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder("Toggle & focus popover", name: .toggleFocus)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
