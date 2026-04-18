import SwiftUI

struct ManualPairView: View {
    let sessionId: String
    let cwd: String
    let candidates: [GhosttyTerminalInfo]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("未紐付けセッション (cwd=\(cwd)) を紐付けるpaneを選択")
                .font(.headline)
                .padding(.bottom, 4)
            List(candidates) { candidate in
                Button {
                    onSelect(candidate.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.name)
                            Text(candidate.workingDir).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("このpaneにfocus") {
                            GhosttyFocus.focus(terminalId: candidate.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(width: 480, height: 300)
        }
        .padding(8)
    }
}
