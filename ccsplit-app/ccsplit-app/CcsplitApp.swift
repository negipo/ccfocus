import SwiftUI

@main
struct CcsplitApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("ccsplit", systemImage: "bubble.left.and.bubble.right") {
            MenuBarView(state: state)
                .task { state.bootstrap() }
        }
        .menuBarExtraStyle(.window)
    }
}
