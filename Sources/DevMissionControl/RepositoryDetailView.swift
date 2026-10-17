import AppKit
import SwiftUI
import DevControlCore

/// Opens one activating detail window per repository (S17). The panel stays
/// compact; triage of many worktrees happens here.
@MainActor
final class RepositoryDetailWindowController {
    private var windows: [String: NSWindow] = [:]

    func show(appState: AppState,
              repoPath: String,
              focusWorktreePath: String?,
              onOpenSettings: @escaping () -> Void) {
        let window: NSWindow
        if let existing = windows[repoPath] {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: RepositoryDetailView(
                appState: appState,
                repoPath: repoPath,
                focusWorktreePath: focusWorktreePath,
                onOpenSettings: onOpenSettings))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 560, height: 640))
            newWindow.isReleasedWhenClosed = false
            window = newWindow
            windows[repoPath] = newWindow
        }

        let name = appState.snapshots.first { $0.config.path == repoPath }?.config.id
            ?? (repoPath as NSString).lastPathComponent
        window.title = "Mission Control — \(name)"
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Local UI state for one repository detail window. Held in an
/// ObservableObject because this environment cannot load the `@State` macro.
@MainActor
final class DetailViewState: ObservableObject {
    @Published var focus: String?
    @Published var showCleanWorktrees: Bool
    @Published var scrollProxy: ScrollViewProxy?

    init(focus: String?, showCleanWorktrees: Bool) {
        self.focus = focus
        self.showCleanWorktrees = showCleanWorktrees
    }
}

/// Read-only repository detail: findings, primary checkout, worktrees ordered
/// conflicts → changes → clean (clean ones collapsed), and source errors.
struct RepositoryDetailView: View {
    @ObservedObject var appState: AppState
    let repoPath: String
    let focusWorktreePath: String?
    let onOpenSettings: () -> Void
    @StateObject private var state: DetailViewState

    private var snapshot: RepoSnapshot? {
        appState.snapshots.first { $0.config.path == repoPath }
    }

    init(appState: AppState, repoPath: String, focusWorktreePath: String?,
         onOpenSettings: @escaping () -> Void) {
        self.appState = appState
        self.repoPath = repoPath
        self.focusWorktreePath = focusWorktreePath
        self.onOpenSettings = onOpenSettings
        // A focused clean worktree must be visible, so start expanded.
        var startExpanded = false
        if let focusWorktreePath,
           let snapshot = appState.snapshots.first(where: { $0.config.path == repoPath }),
           let worktree = snapshot.git.worktrees.first(where: { $0.path == focusWorktreePath }),
           WorktreeOrdering.rank(worktree) == 2 {
            startExpanded = true
        }
        self._state = StateObject(wrappedValue: DetailViewState(
            focus: focusWorktreePath, showCleanWorktrees: startExpanded))
    }

    var body: some View {
        Group {
            if let snapshot {
                detail(snapshot)
            } else {
                VStack(spacing: 8) {
                    Text("Sin datos para este proyecto.")
                        .font(.headline)
                    Text("Cerrá esta ventana y volvé a abrirla desde el panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 600)
    }

    private func detail(_ snapshot: RepoSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(snapshot)
                    SourceFreshnessRow(snapshot: snapshot)
                    findingsSection(snapshot)
                    checkoutSection(snapshot)
                    worktreesSection(snapshot)
                    sourceErrors(snapshot)
                }
                .padding(.bottom, 8)
            }
            .onAppear {
                state.scrollProxy = proxy
                if let focus = state.focus { proxy.scrollTo(focus, anchor: .top) }
            }
            .onChange(of: state.focus) { target in
                if let target { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    // MARK: - Sections

    private func header(_ snapshot: RepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.config.id)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if snapshot.config.isPaused {
                    Label("Pausado", systemImage: "pause.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.4), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                Text("Principal ·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(primaryBranchLabel(snapshot))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(snapshot.git.worktrees.count) worktree\(snapshot.git.worktrees.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.config.path)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func findingsSection(_ snapshot: RepoSnapshot) -> some View {
        let items = appState.items(for: snapshot)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hallazgos actuales")
                    .font(.caption.weight(.semibold))
                ForEach(items) { item in
                    Button {
                        if let path = item.worktreePath {
                            state.focus = path
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(color(for: item.severity))
                                .frame(width: 6, height: 6)
                            Text(item.message)
                                .font(.caption)
                                .foregroundStyle(item.severity == .info ? Color.secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 2)
                            if item.worktreePath != nil {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.worktreePath == nil
                                        ? item.message
                                        : "Ir a \(item.message)")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func checkoutSection(_ snapshot: RepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Checkout principal · \(primaryBranchLabel(snapshot))")
                .font(.caption.weight(.semibold))
            Text(changeSummary(snapshot.git.changes))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if snapshot.git.unpushedCount > 0 {
                Text("\(snapshot.git.unpushedCount) commit\(snapshot.git.unpushedCount == 1 ? "" : "s") sin subir")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// S17: conflicted worktrees first, then changed ones; clean worktrees
    /// stay collapsed under “Ver los N worktrees limpios”.
    @ViewBuilder
    private func worktreesSection(_ snapshot: RepoSnapshot) -> some View {
        let items = appState.items(for: snapshot)
        let all = WorktreeOrdering.sortedForTriage(snapshot.git.worktrees)
        let active = all.filter { WorktreeOrdering.rank($0) < 2 }
        let clean = all.filter { WorktreeOrdering.rank($0) == 2 }

        VStack(alignment: .leading, spacing: 4) {
            if snapshot.git.freshness == .unavailable {
                Text("Worktrees no disponibles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if all.isEmpty {
                Text("Sin worktrees adicionales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Worktrees")
                    .font(.caption.weight(.semibold))
                ForEach(active, id: \.path) { worktree in
                    triageRow(worktree, items: items)
                }
                if !clean.isEmpty {
                    DisclosureGroup(
                        isExpanded: $state.showCleanWorktrees,
                        content: {
                            ForEach(clean, id: \.path) { worktree in
                                triageRow(worktree, items: items)
                            }
                        },
                        label: {
                            Text("\(state.showCleanWorktrees ? "Ocultar" : "Ver") \(clean.count) worktree\(clean.count == 1 ? "" : "s") limpio\(clean.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        })
                }
            }
        }
    }

    private func triageRow(_ worktree: WorktreeInfo, items: [AttentionItem]) -> some View {
        WorktreeTriageRow(
            worktree: worktree,
            severity: items.first(where: { $0.worktreePath == worktree.path })?.severity ?? .info,
            editorApplicationPath: appState.config.editorApplicationPath,
            pullRequest: snapshot?.associatedPullRequest(for: worktree),
            isFocused: state.focus == worktree.path,
            onConfigureEditor: onOpenSettings)
        .id(worktree.path)
    }

    @ViewBuilder
    private func sourceErrors(_ snapshot: RepoSnapshot) -> some View {
        let errors: [(String, String?)] = [
            ("Git", snapshot.git.error),
            ("GitHub", snapshot.pr.error),
            ("Engram", snapshot.activity.error)
        ]
        let present = errors.compactMap { source, error -> String? in
            guard let error else { return nil }
            return "\(source): \(error)"
        }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(present, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Helpers

    private func primaryBranchLabel(_ snapshot: RepoSnapshot) -> String {
        if let branch = snapshot.git.branch { return branch }
        return snapshot.git.freshness == .unavailable ? "no disponible" : "detached"
    }

    private func changeSummary(_ changes: ChangeCounts) -> String {
        var parts = [
            "Staged \(changes.staged)",
            "Unstaged \(changes.unstaged)",
            "Untracked \(changes.untracked)"
        ]
        if changes.conflicts > 0 {
            parts.append("Conflictos \(changes.conflicts)")
        }
        return parts.joined(separator: " · ")
    }

    private func color(for severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}
