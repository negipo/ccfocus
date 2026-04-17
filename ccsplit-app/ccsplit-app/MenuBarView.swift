import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var onDismiss: () -> Void = {}
    @State private var showDeceased = false

    private var activeSessions: [SessionEntry] {
        state.registry.sortedByLastEventDesc().filter { $0.status != .deceased }
    }

    private var deceasedSessions: [SessionEntry] {
        state.registry.sortedByLastEventDesc().filter { $0.status == .deceased }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.registry.sessions.isEmpty {
                Text("No sessions").foregroundStyle(.secondary)
            } else {
                ForEach(activeSessions, id: \.sessionId) { s in
                    row(s)
                }
                if !deceasedSessions.isEmpty {
                    Divider()
                    HStack {
                        Image(systemName: showDeceased ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text("deceased (\(deceasedSessions.count))")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { showDeceased.toggle() }
                    if showDeceased {
                        ForEach(deceasedSessions, id: \.sessionId) { s in
                            row(s)
                        }
                    }
                }
            }
            Divider()
            Button("Quit ccsplit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(8)
        .frame(minWidth: 320)
    }

    private var isUnlinked: (SessionEntry) -> Bool {
        { s in
            [.running, .waitingInput, .done].contains(s.status)
                && state.effectiveTerminalId(for: s) == nil
        }
    }

    private func row(_ s: SessionEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(color(for: s.status)).frame(width: 10, height: 10)
                if isUnlinked(s) {
                    Image(systemName: "link.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text((s.cwd as NSString).lastPathComponent).fontWeight(s.status == .waitingInput ? .semibold : .regular)
                if let b = s.gitBranch { Text("[\(b)]").foregroundStyle(.secondary) }
                Spacer()
                Text(relativeAge(s.lastEventTs)).foregroundStyle(.secondary)
            }
            if s.status == .waitingInput, let msg = s.lastMessage {
                Text(msg).font(.caption).foregroundStyle(.orange).padding(.leading, 16)
            }
        }
        .padding(4)
        .background(s.status == .waitingInput ? Color.orange.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.clearMessage(s.sessionId)
            if let id = state.effectiveTerminalId(for: s) {
                GhosttyFocus.focus(terminalId: id)
                onDismiss()
            }
        }
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
