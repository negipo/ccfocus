import SwiftUI

@main
struct CcsplitApp: App {
    var body: some Scene {
        MenuBarExtra("ccsplit", systemImage: "bubble.left.and.bubble.right") {
            Text("ccsplit (skeleton)")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
