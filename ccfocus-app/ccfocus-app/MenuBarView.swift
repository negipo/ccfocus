import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    @State private var showDeceased = false

    private var activeSessions: [SessionEntry] {
        state.registry.sortedByLastEventDesc().filter { $0.status != .deceased }
    }

    private var deceasedSessions: [SessionEntry] {
        state.registry.sortedByLastEventDesc().filter { $0.status == .deceased }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if activeSessions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No active sessions").foregroundStyle(.secondary)
                    Text("Start a new Claude Code session to get going.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(4)
            } else {
                ForEach(Array(activeSessions.enumerated()), id: \.element.sessionId) { idx, s in
                    row(s, numberHint: numberHint(forIndex: idx))
                }
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
                    let rowHeight: CGFloat = 28
                    let maxVisible: CGFloat = 19.5
                    let height = min(CGFloat(deceasedSessions.count) * rowHeight, maxVisible * rowHeight)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(deceasedSessions, id: \.sessionId) { s in
                                row(s, numberHint: nil)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: height)
                }
            }
            Divider()
            HStack {
                Color.clear.frame(width: 10, height: 10)
                Text("Settings").foregroundStyle(.secondary)
                Spacer()
                Text("⌘,").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture {
                onDismiss()
                onOpenSettings()
            }
            Divider()
            HStack {
                Color.clear.frame(width: 10, height: 10)
                Text("Quit").foregroundStyle(.secondary)
                Spacer()
                Text("⌘Q").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture { NSApp.terminate(nil) }
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

    private func numberHint(forIndex idx: Int) -> String? {
        guard idx < 10 else { return nil }
        return idx == 9 ? "0" : String(idx + 1)
    }

    private func row(_ s: SessionEntry, numberHint: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(color(for: s.status)).frame(width: 10, height: 10)
                if isUnlinked(s) {
                    Image(systemName: "link.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text((s.cwd as NSString).lastPathComponent)
                    .fontWeight(s.status == .waitingInput ? .semibold : .regular)
                    .lineLimit(1)
                if let b = s.gitBranch {
                    Text("[\(b)]")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(-1)
                }
                Spacer()
                Text(relativeAge(s.lastEventTs)).foregroundStyle(.secondary)
                if let numberHint {
                    Text(numberHint).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            if s.status == .waitingInput, let msg = s.lastMessage {
                Text(msg).font(.caption).foregroundStyle(.orange).padding(.leading, 16)
            }
            if s.status == .done, s.doneNotified {
                Text("done").font(.caption).foregroundStyle(.secondary).padding(.leading, 16)
            }
        }
        .padding(4)
        .background(
            s.status == .waitingInput ? Color.orange.opacity(0.1) :
            s.status == .done && s.doneNotified ? Color.gray.opacity(0.1) :
            Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.clearMessage(s.sessionId)
            state.clearDoneNotified(s.sessionId)
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
