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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let state = AppState()
    private var stateMachine = PopoverStateMachine()
    private let hotkeyController = HotkeyController()
    private let settingsWindowController = SettingsWindowController()
    private var keyObservers: [NSObjectProtocol] = []
    private var clickOutsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItemIfNeeded()
        state.bootstrap()
        state.onOpenPopover = { [weak self] in self?.showPanelUnfocused() }
        state.onClosePopover = { [weak self] in
            guard let self else { return }
            self.closePanel(reason: .attentionCleared)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right",
                accessibilityDescription: "ccfocus"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        let menuView = MenuBarView(
            state: state,
            onDismiss: { [weak self] in self?.closePanel(reason: .committedViaRow) },
            onOpenSettings: { [weak self] in self?.settingsWindowController.show() },
            onCycleOneStep: { [weak self] in self?.peekOneStep(forward: true) }
        )
        let hostingView = KeyHandlingHostingView(rootView: menuView)
        hostingView.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }

        let panelRect = NSRect(x: 0, y: 0, width: 340, height: 10)
        panel = NSPanel(contentRect: panelRect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isMovable = false
        panel.contentView = hostingView

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
        if panel.isVisible { closePanel(reason: .statusButtonToggle); return }
        showPanelUnfocused()
    }

    private func handleHotkey() {
        if panel.isVisible {
            if panel.isKeyWindow { closePanel(reason: .userHotkey) } else { focusPanel() }
        } else {
            showPanelUnfocused()
            focusPanel()
        }
    }

    private func showPanelUnfocused() {
        guard let button = statusItem.button, let window = button.window else { return }
        if panel.isVisible { return }
        let buttonRectOnScreen = window.convertToScreen(button.frame)
        let origin = NSPoint(x: buttonRectOnScreen.midX - panel.frame.width / 2,
                             y: buttonRectOnScreen.minY - panel.frame.height)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        if let host = panel.contentView as? KeyHandlingHostingView<MenuBarView> {
            host.wantsKeyboardFocus = false
        }
        state.capturePreviousFrontmostApp()
        stateMachine.markOpenedUnfocused()
        observeKeyWindowNotifications()
        installClickOutsideMonitorIfNeeded()
    }

    private func installClickOutsideMonitorIfNeeded() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.panel.isVisible else { return }
                self.closePanel(reason: .clickOutside)
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func focusPanel() {
        NSApp.activate(ignoringOtherApps: true)
        if let host = panel.contentView as? KeyHandlingHostingView<MenuBarView> {
            host.wantsKeyboardFocus = true
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(host)
        }
    }

    func peekOneStep(forward: Bool) {
        guard state.cycleSessionsOneStep(forward: forward) != nil,
              let tid = state.lastPeekedTerminalId else { return }
        GhosttyFocus.peek(terminalId: tid)
        DispatchQueue.main.async { [weak self] in self?.panel.orderFront(nil) }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        if event.keyCode == 53 {
            closePanel(reason: .userEscape)
            return true
        }
        if event.keyCode == 48 {
            let forward = !event.modifierFlags.contains(.shift)
            peekOneStep(forward: forward)
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
            closePanel(reason: .committedViaNumberKey)
        }
        return true
    }

    private func observeKeyWindowNotifications() {
        keyObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyObservers.removeAll()
        let center = NotificationCenter.default
        let becameKey = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stateMachine.markBecameKey() }
        }
        let resignedKey = center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stateMachine.markResignedKey() }
        }
        let willClose = center.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.stateMachine.markDidClose()
                if let host = self?.panel.contentView as? KeyHandlingHostingView<MenuBarView> {
                    host.wantsKeyboardFocus = false
                }
            }
        }
        keyObservers = [becameKey, resignedKey, willClose]
    }

    func closePanel(reason: PanelCloseReason) {
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        let decision = PanelCloseDecision.decide(
            reason: reason,
            isPeekActive: state.lastPeekedTerminalId != nil,
            isCcfocusFrontmost: isFrontmost
        )
        guard decision.shouldClose else { return }
        if decision.shouldCommit { state.commitLastPeek() }
        if decision.shouldRestoreFrontmost { state.restorePreviousFrontmostApp() }
        state.resetCycleState()
        panel.close()
        removeClickOutsideMonitor()
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
