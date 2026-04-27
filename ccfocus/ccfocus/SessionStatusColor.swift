import SwiftUI

extension SessionStatus {
    var displayColor: Color {
        switch self {
        case .idle: return .gray
        case .running: return .green
        case .asking: return .orange
        case .waitingInput: return .orange
        case .done: return .gray
        case .error: return .red
        case .stale: return Color.gray.opacity(0.4)
        case .deceased: return Color.gray.opacity(0.2)
        }
    }
}
