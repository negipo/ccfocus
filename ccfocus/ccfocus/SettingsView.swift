import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)
            HStack {
                Text("Toggle & focus popover:")
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleFocus)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 140, alignment: .topLeading)
    }
}
