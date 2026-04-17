import AppKit
import ServiceManagement
import SwiftUI

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@main
struct CcsplitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItemIfNeeded()
        state.bootstrap()
        state.onOpenPopover = { [weak self] in self?.showPopover() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "ccsplit")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        let vc = NSViewController()
        vc.view = FirstMouseHostingView(
            rootView: MenuBarView(state: state) { [weak self] in self?.popover.performClose(nil) }
        )
        popover.contentViewController = vc
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func registerLoginItemIfNeeded() {
        let key = "loginItemRegistered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try? service.register()
        }
        UserDefaults.standard.set(true, forKey: key)
    }
}
