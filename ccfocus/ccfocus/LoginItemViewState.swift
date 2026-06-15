import ServiceManagement

struct LoginItemViewState: Equatable {
    let isEnabled: Bool
    let needsApproval: Bool
    let approvalText: String?

    init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            isEnabled = true
            needsApproval = false
            approvalText = nil
        case .requiresApproval:
            isEnabled = true
            needsApproval = true
            approvalText = "Approval required — enable ccfocus in System Settings › Login Items"
        case .notRegistered, .notFound:
            isEnabled = false
            needsApproval = false
            approvalText = nil
        @unknown default:
            isEnabled = false
            needsApproval = false
            approvalText = nil
        }
    }
}
