import AppKit
import Combine
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
                attentionRow(item)
            }
            unavailableLine
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        if item.kind == .staleWorktree,
           let path = item.worktreePath,
           let worktree = snapshot.git.worktrees.first(where: { $0.path == path }) {
            WorktreeTriageRow(
                worktree: worktree, severity: item.severity,
                editorApplicationPath: appState.config.editorApplicationPath,
                pullRequest: snapshot.associatedPullRequest(for: worktree))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(color(for: item.severity))
                    .frame(width: 6, height: 6)
                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(item.severity == .info ? .secondary : .primary)
            }
        }
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

/// Local UI state for one worktree's asynchronous actions.
@MainActor
private final class WorktreeActionState: ObservableObject {
    @Published var isLoadingDiff = false
    @Published var showingDiff = false
    @Published var diffText = ""
    @Published var actionError: String?
}

/// Detailed, read-only triage row for a linked worktree.
struct WorktreeTriageRow: View {
    let worktree: WorktreeInfo
    let severity: AttentionItem.Severity
    let editorApplicationPath: String?
    let pullRequest: PRInfo?
    @StateObject private var actionState = WorktreeActionState()

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Circle()
                .fill(severityColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worktree.name)
                        .font(.caption.weight(.semibold))
                    Text(worktree.branch ?? "detached")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(statusSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(worktree.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 2)
            Menu {
                Button {
                    openEditor()
                } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                }
                .disabled(editorApplicationPath == nil)

                Button {
                    openTerminal()
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                }

                Button {
                    showDiff()
                } label: {
                    Label(actionState.isLoadingDiff ? "Preparing Diff…" : "Show Diff",
                          systemImage: "doc.text.magnifyingglass")
                }
                .disabled(actionState.isLoadingDiff)

                if let pullRequest {
                    Button {
                        openPullRequest(pullRequest)
                    } label: {
                        Label("Open PR #\(pullRequest.number)",
                              systemImage: "arrow.up.right.square")
                    }
                }

                Divider()
                Button(action: revealInFinder) {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button(action: copyPath) {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Actions for \(worktree.name)")
            .accessibilityLabel("Actions for \(worktree.name)")
        }
        .padding(.vertical, 3)
        .sheet(isPresented: $actionState.showingDiff) {
            WorktreeDiffSheet(worktreeName: worktree.name, diff: actionState.diffText)
        }
        .alert("Worktree Action Failed", isPresented: Binding(
            get: { actionState.actionError != nil },
            set: { if !$0 { actionState.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionState.actionError = nil }
        } message: {
            Text(actionState.actionError ?? "Unknown error")
        }
    }

    private var statusSummary: String {
        let commitAge: String
        if worktree.lastCommitAt == nil {
            commitAge = "last commit date unavailable"
        } else if worktree.ageDays == 0 {
            commitAge = "last commit today"
        } else {
            commitAge = "last commit \(worktree.ageDays) day\(worktree.ageDays == 1 ? "" : "s") ago"
        }

        if worktree.dirtyCount == 0 {
            return "Clean · \(commitAge)"
        }
        return "\(worktree.dirtyCount) changed file\(worktree.dirtyCount == 1 ? "" : "s") · \(commitAge)"
    }

    private var severityColor: Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func openEditor() {
        guard let editorApplicationPath else {
            actionState.actionError = "Choose an editor in Settings first."
            return
        }
        launch(WorktreeActionCommand.openApplication(
            appPath: editorApplicationPath, worktreePath: worktree.path))
    }

    private func openTerminal() {
        launch(WorktreeActionCommand.openTerminal(worktreePath: worktree.path))
    }

    private func launch(_ command: WorktreeActionCommand) {
        Task { @MainActor in
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    _ = try ProcessRunner().run(command.executable, command.arguments, in: nil)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let error { actionState.actionError = error }
        }
    }

    private func showDiff() {
        actionState.isLoadingDiff = true
        let command = WorktreeActionCommand.gitDiff(worktreePath: worktree.path)
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do {
                    return (try ProcessRunner().run(command.executable, command.arguments, in: nil), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            actionState.isLoadingDiff = false
            if let error = result.1 {
                actionState.actionError = error
            } else {
                actionState.diffText = result.0 ?? ""
                actionState.showingDiff = true
            }
        }
    }

    private func openPullRequest(_ pullRequest: PRInfo) {
        guard let url = pullRequest.webURL else {
            actionState.actionError = "This pull request has no safe HTTPS URL."
            return
        }
        if !NSWorkspace.shared.open(url) {
            actionState.actionError = "Could not open pull request #\(pullRequest.number)."
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: worktree.path, isDirectory: true)
        ])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(worktree.path, forType: .string)
    }
}

private struct WorktreeDiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let worktreeName: String
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Diff · \(worktreeName)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            if diff.isEmpty {
                Text("No tracked changes relative to HEAD. Untracked files are not included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(diff)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
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
