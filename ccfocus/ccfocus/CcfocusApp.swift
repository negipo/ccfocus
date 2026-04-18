import AppKit
import ServiceManagement
import SwiftUI

@main
struct CcfocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = AppState()
    private var stateMachine = PopoverStateMachine()
    private let hotkeyController = HotkeyController()
    private let settingsWindowController = SettingsWindowController()
    private var keyObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItemIfNeeded()
        state.bootstrap()
        state.onOpenPopover = { [weak self] in self?.showPopoverUnfocused() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right",
                accessibilityDescription: "ccfocus"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let viewController = NSViewController()
        let menuView = MenuBarView(
            state: state,
            onDismiss: { [weak self] in self?.popover.performClose(nil) },
            onOpenSettings: { [weak self] in self?.settingsWindowController.show() }
        )
        let hostingView = KeyHandlingHostingView(rootView: menuView)
        hostingView.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        viewController.view = hostingView
        popover.contentViewController = viewController

        hotkeyController.onToggleFocus = { [weak self] in self?.handleHotkey() }
        hotkeyController.start()

        setupMainMenu()
        observeKeyWindowNotifications()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        settingsWindowController.show()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopoverUnfocused()
        }
    }

    private func handleHotkey() {
        if popover.isShown {
            let isKey = popover.contentViewController?.view.window?.isKeyWindow ?? false
            if isKey {
                popover.performClose(nil)
            } else {
                focusPopover()
            }
        } else {
            showPopoverUnfocused()
            focusPopover()
        }
    }

    private func showPopoverUnfocused() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            if let hostingView = popover.contentViewController?.view as? KeyHandlingHostingView<MenuBarView> {
                hostingView.wantsKeyboardFocus = false
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            observeKeyWindowNotifications()
            stateMachine.markOpenedUnfocused()
        }
    }

    private func focusPopover() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = popover.contentViewController?.view.window,
           let hostingView = popover.contentViewController?.view as? KeyHandlingHostingView<MenuBarView> {
            hostingView.wantsKeyboardFocus = true
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(hostingView)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard popover.contentViewController?.view.window?.isKeyWindow == true else { return false }
        if event.keyCode == 53 {
            popover.performClose(nil)
            return true
        }
        guard let chars = event.charactersIgnoringModifiers, let character = chars.first,
              let index = KeyActionResolver.numberIndex(forCharacter: character) else {
            return false
        }
        let entries = state.registry.sortedByLastEventDesc().filter { $0.status != .deceased }
        guard let entry = KeyActionResolver.select(from: entries, numberIndex: index) else { return false }
        state.clearMessage(entry.sessionId)
        state.clearDoneNotified(entry.sessionId)
        if let id = state.effectiveTerminalId(for: entry) {
            GhosttyFocus.focus(terminalId: id)
            popover.performClose(nil)
        }
        return true
    }

    private func observeKeyWindowNotifications() {
        keyObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyObservers.removeAll()
        guard let window = popover.contentViewController?.view.window else { return }
        let center = NotificationCenter.default
        let becameKey = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stateMachine.markBecameKey() }
        }
        let resignedKey = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stateMachine.markResignedKey() }
        }
        keyObservers = [becameKey, resignedKey]
    }

    func popoverDidClose(_ notification: Notification) {
        if let hostingView = popover.contentViewController?.view as? KeyHandlingHostingView<MenuBarView> {
            hostingView.wantsKeyboardFocus = false
        }
        stateMachine.markDidClose()
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
