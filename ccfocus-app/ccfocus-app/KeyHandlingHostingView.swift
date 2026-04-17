import AppKit
import SwiftUI

final class KeyHandlingHostingView<Content: View>: NSHostingView<Content> {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if let onKeyDown, onKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
