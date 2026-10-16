import SwiftUI
import DevControlCore

/// Root view of the status panel: header with attention count and refresh,
/// attention cards first, clean projects compact, footer with settings.
struct MissionControlPanelView: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            ScrollView {
                VStack(spacing: 12) {
                    if appState.snapshots.isEmpty {
                        emptyState
                    } else {
                        if !appState.attentionOrder.isEmpty {
                            sectionTitle("Needs attention")
                            ForEach(appState.attentionOrder, id: \.config.id) { snapshot in
                                ProjectCard(appState: appState, snapshot: snapshot)
                            }
                        }
                        if !appState.cleanOrder.isEmpty {
                            sectionTitle("Clean")
                            VStack(spacing: 6) {
                                ForEach(appState.cleanOrder, id: \.config.id) { snapshot in
                                    CleanRow(snapshot: snapshot)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
            Divider().opacity(0.25)
            footer
        }
        .frame(width: 380, height: 520)
        .background(VisualEffectBackground().ignoresSafeArea())
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.gradient)
            Text("Mission Control")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(appState.attentionCount == 0 ? "All clear"
                        : "\(appState.attentionCount) need attention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appState.attentionCount == 0 ? .green : .orange)
                Text(lastRefreshLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            refreshButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var lastRefreshLabel: String {
        guard let last = appState.lastRefresh else { return "never scanned" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: last)
    }

    @ViewBuilder private var refreshButton: some View {
        if appState.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .padding(.leading, 4)
        } else {
            Button {
                appState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.leading, 4)
            .help("Scan all projects")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.config.repos.isEmpty ? "No projects tracked yet" : "Scanning…")
                .font(.headline)
            if appState.config.repos.isEmpty {
                Text("Add repositories to see PRs, CI, worktrees\nand last agent activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings", action: onOpenSettings)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("Dev Mission Control")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings", action: onOpenSettings)
                .controlSize(.small)
            Button("Quit", action: onQuit)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Card for a repository with at least one attention item.
struct ProjectCard: View {
    @ObservedObject var appState: AppState
    let snapshot: RepoSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.config.id)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(snapshot.git.branch ?? "detached")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(appState.items(for: snapshot)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(color(for: item.severity))
                        .frame(width: 6, height: 6)
                    Text(item.message)
                        .font(.caption)
                        .foregroundStyle(item.severity == .info ? .secondary : .primary)
                }
            }
            unavailableLine
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// S5: sources that could not be consulted surface as unavailable,
    /// never as fabricated findings.
    private var unavailableNotes: [String] {
        var notes: [String] = []
        if !snapshot.pr.available { notes.append("PRs unavailable") }
        if !snapshot.activity.available { notes.append("Engram unavailable") }
        return notes
    }

    @ViewBuilder private var unavailableLine: some View {
        if !unavailableNotes.isEmpty {
            Text(unavailableNotes.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func color(for severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

/// Compact row for a repository with nothing to flag.
struct CleanRow: View {
    let snapshot: RepoSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text(snapshot.config.id)
                .font(.caption.weight(.medium))
            Spacer()
            if snapshot.activity.available, let activity = snapshot.activity.activity {
                Text(activity.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
