import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCycleOneStep: () -> Void = {}
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
                ForEach(Array(activeSessions.enumerated()), id: \.element.sessionId) { idx, session in
                    row(session, numberHint: numberHint(forIndex: idx))
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
                            ForEach(deceasedSessions, id: \.sessionId) { session in
                                row(session, numberHint: nil)
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
                Text("Cycle sessions").foregroundStyle(.secondary)
                Spacer()
                Text("Tab").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture { onCycleOneStep() }
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
        { session in
            [.idle, .running, .asking, .waitingInput, .done].contains(session.status)
                && state.effectiveTerminalId(for: session) == nil
        }
    }

    private func numberHint(forIndex idx: Int) -> String? {
        guard idx < 10 else { return nil }
        return idx == 9 ? "0" : String(idx + 1)
    }

    private func isPeeked(_ session: SessionEntry) -> Bool {
        state.lastPeekedSessionId == session.sessionId
    }

    private func row(_ session: SessionEntry, numberHint: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            rowHeader(session, numberHint: numberHint)
            rowStatusDetail(session)
        }
        .padding(4)
        .background(backgroundColor(for: session))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isPeeked(session) ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.clearMessage(session.sessionId)
            state.clearDoneNotified(session.sessionId)
            if let id = state.effectiveTerminalId(for: session) {
                GhosttyFocus.focus(terminalId: id)
                onDismiss()
            }
        }
    }

    private func rowHeader(_ session: SessionEntry, numberHint: String?) -> some View {
        HStack {
            Circle().fill(color(for: session.status)).frame(width: 10, height: 10)
            if isUnlinked(session) {
                Image(systemName: "link.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text((session.cwd as NSString).lastPathComponent)
                .fontWeight(session.status == .waitingInput ? .semibold : .regular)
                .lineLimit(1)
            if let branch = session.gitBranch {
                Text("[\(branch)]")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Spacer()
            Text(relativeAge(session.lastEventTs)).foregroundStyle(.secondary)
            if let numberHint {
                Text(numberHint).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func rowStatusDetail(_ session: SessionEntry) -> some View {
        if session.status == .waitingInput, let msg = session.lastMessage {
            Text(msg).font(.caption).foregroundStyle(.orange).padding(.leading, 16)
        }
        if session.status == .asking {
            Text(session.lastMessage ?? "asking")
                .font(.caption).foregroundStyle(.orange).padding(.leading, 16)
        }
        if session.status == .done, session.doneNotified {
            Text("done").font(.caption).foregroundStyle(.secondary).padding(.leading, 16)
        }
        if session.status == .idle {
            Text("idle").font(.caption).foregroundStyle(.secondary).padding(.leading, 16)
        }
    }

    private func backgroundColor(for session: SessionEntry) -> Color {
        if session.status == .asking { return Color.orange.opacity(0.1) }
        if session.status == .waitingInput { return Color.orange.opacity(0.1) }
        if session.status == .done && session.doneNotified { return Color.gray.opacity(0.1) }
        if session.status == .idle { return Color.gray.opacity(0.1) }
        return Color.clear
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
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

    private func relativeAge(_ timestamp: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: timestamp) else { return "" }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds/60)m" }
        return "\(seconds/3600)h"
    }
}
