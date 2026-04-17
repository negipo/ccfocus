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
            List(candidates) { c in
                Button {
                    onSelect(c.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.name)
                            Text(c.wd).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("このpaneにfocus") {
                            GhosttyFocus.focus(terminalId: c.id)
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
