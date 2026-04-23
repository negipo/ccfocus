import Foundation

enum PanelCloseReason {
    case userEscape
    case userHotkey
    case committedViaRow
    case committedViaNumberKey
    case attentionCleared
    case statusButtonToggle
    case clickOutside
}

struct PanelCloseDecision {
    let shouldClose: Bool
    let shouldCommit: Bool
    let shouldRestoreFrontmost: Bool

    static func decide(reason: PanelCloseReason, isPeekActive: Bool, isCcfocusFrontmost: Bool, panelUserOwned: Bool) -> PanelCloseDecision {
        if reason == .attentionCleared && panelUserOwned {
            return PanelCloseDecision(shouldClose: false, shouldCommit: false, shouldRestoreFrontmost: false)
        }
        if reason == .attentionCleared && isPeekActive {
            return PanelCloseDecision(shouldClose: false, shouldCommit: false, shouldRestoreFrontmost: false)
        }
        switch reason {
        case .committedViaRow, .committedViaNumberKey:
            return PanelCloseDecision(shouldClose: true, shouldCommit: false, shouldRestoreFrontmost: false)
        case .userEscape, .userHotkey, .statusButtonToggle:
            return PanelCloseDecision(
                shouldClose: true,
                shouldCommit: isPeekActive,
                shouldRestoreFrontmost: !isPeekActive && isCcfocusFrontmost
            )
        case .clickOutside:
            return PanelCloseDecision(
                shouldClose: true,
                shouldCommit: false,
                shouldRestoreFrontmost: false
            )
        case .attentionCleared:
            return PanelCloseDecision(
                shouldClose: true,
                shouldCommit: false,
                shouldRestoreFrontmost: isCcfocusFrontmost
            )
        }
    }
}
