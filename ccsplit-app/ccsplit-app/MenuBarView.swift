import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.registry.sessions.isEmpty {
                Text("No sessions").foregroundStyle(.secondary)
            } else {
                ForEach(state.registry.sortedByLastEventDesc(), id: \.sessionId) { s in
                    row(s)
                }
            }
            Divider()
            Button("Quit ccsplit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(8)
        .frame(minWidth: 320)
    }

    private func row(_ s: SessionEntry) -> some View {
        Button {
            if let id = s.terminalId { GhosttyFocus.focus(terminalId: id) }
        } label: {
            HStack {
                Circle().fill(color(for: s.status)).frame(width: 10, height: 10)
                Text((s.cwd as NSString).lastPathComponent)
                if let b = s.gitBranch {
                    Text("[\(b)]").foregroundStyle(.secondary)
                }
                Spacer()
                Text(relativeAge(s.lastEventTs)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func color(for s: SessionStatus) -> Color {
        switch s {
        case .running: return .green
        case .waitingInput: return .orange
        case .done: return .gray
        case .error: return .red
        case .stale: return Color.gray.opacity(0.4)
        case .deceased: return Color.gray.opacity(0.2)
        }
    }

    private func relativeAge(_ ts: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = fmt.date(from: ts) else { return "" }
        let s = Int(-d.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m" }
        return "\(s/3600)h"
    }
}
