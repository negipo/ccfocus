import SwiftUI

struct CycleHUDModel: Equatable {
    var projectName: String
    var statusColor: Color

    static let empty = CycleHUDModel(projectName: "", statusColor: .clear)
}

struct CycleHUDView: View {
    let model: CycleHUDModel

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 28, height: 28)
            Text(model.projectName)
                .font(.system(size: 44, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}
