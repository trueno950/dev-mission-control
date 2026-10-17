import AppKit
import SwiftUI
import DevControlCore

/// Opens one activating detail window per repository (S17). The panel stays
/// compact; triage of many worktrees happens here. The view state is kept per
/// repository so a reused window applies the newly requested notice focus
/// instead of silently dropping it.
@MainActor
final class RepositoryDetailWindowController {
    private var windows: [String: NSWindow] = [:]
    private var states: [String: DetailViewState] = [:]

    func show(appState: AppState,
              repoPath: String,
              focusWorktreePath: String?,
              onOpenSettings: @escaping () -> Void,
              onOpenEngramPanel: @escaping () -> Void) {
        let state: DetailViewState
        if let existing = states[repoPath] {
            state = existing
        } else {
            state = DetailViewState(focus: focusWorktreePath,
                                    showCleanWorktrees: focusedWorktreeIsClean(
                                        appState: appState, repoPath: repoPath,
                                        focus: focusWorktreePath))
            states[repoPath] = state
        }

        let window: NSWindow
        if let existing = windows[repoPath] {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: RepositoryDetailView(
                appState: appState,
                repoPath: repoPath,
                state: state,
                onOpenSettings: onOpenSettings,
                onOpenEngramPanel: onOpenEngramPanel))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 560, height: 640))
            newWindow.isReleasedWhenClosed = false
            window = newWindow
            windows[repoPath] = newWindow
        }

        // Forward the focus on every presentation, including reuse. Clearing
        // first makes re-selecting the same notice still trigger the change.
        state.focus = nil
        state.focus = focusWorktreePath
        if focusedWorktreeIsClean(appState: appState, repoPath: repoPath,
                                  focus: focusWorktreePath) {
            state.showCleanWorktrees = true
        }

        let name = appState.snapshots.first { $0.config.path == repoPath }?.config.id
            ?? (repoPath as NSString).lastPathComponent
        window.title = "Mission Control — \(name)"
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func focusedWorktreeIsClean(appState: AppState,
                                        repoPath: String,
                                        focus: String?) -> Bool {
        guard let focus,
              let snapshot = appState.snapshots.first(where: { $0.config.path == repoPath }),
              let worktree = snapshot.git.worktrees.first(where: { $0.path == focus }) else {
            return false
        }
        return WorktreeOrdering.rank(worktree) == 2
    }
}

/// Local UI state for one repository detail window. Owned by the window
/// controller and shared with the view, so a reused window can apply a newly
/// requested focus. Held in an ObservableObject because this environment
/// cannot load the `@State` macro.
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
    @ObservedObject var state: DetailViewState
    let onOpenSettings: () -> Void
    let onOpenEngramPanel: () -> Void

    private var snapshot: RepoSnapshot? {
        appState.snapshots.first { $0.config.path == repoPath }
    }

    init(appState: AppState, repoPath: String, state: DetailViewState,
         onOpenSettings: @escaping () -> Void,
         onOpenEngramPanel: @escaping () -> Void) {
        self.appState = appState
        self.repoPath = repoPath
        self.state = state
        self.onOpenSettings = onOpenSettings
        self.onOpenEngramPanel = onOpenEngramPanel
    }

    var body: some View {
        Group {
            if let snapshot {
                detail(snapshot)
            } else {
                VStack(spacing: 8) {
                    Text(L10n.t("Sin datos para este proyecto.", "No data for this project."))
                        .font(.headline)
                    Text(L10n.t("Cerrá esta ventana y volvé a abrirla desde el panel.", "Close this window and reopen it from the panel."))
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
                    engramPanelEntry
                    SourceFreshnessRow(snapshot: snapshot, showsMemoriesAction: true,
                                       onOpenEngramPanel: onOpenEngramPanel)
                    findingsSection(snapshot)
                    pullRequestsSection(snapshot)
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

    /// T17 visible entry point: opens the per-project Engram panel window.
    private var engramPanelEntry: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.book.closed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.t("Memorias de Engram", "Engram memories"))
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            Button {
                onOpenEngramPanel()
            } label: {
                Label(L10n.t("Abrir panel", "Open panel"), systemImage: "square.grid.2x2")
            }
            .controlSize(.small)
            .help(L10n.t("Abre el panel de memorias de Engram de este proyecto",
                         "Opens this project's Engram memories panel"))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func header(_ snapshot: RepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.config.id)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if snapshot.config.isPaused {
                    Label(L10n.t("Pausado", "Paused"), systemImage: "pause.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.4), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                Text(L10n.t("Principal ·", "Primary ·"))
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
                Text(L10n.t("Hallazgos actuales", "Current findings"))
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

    /// S20: open PRs with a direct browser link using only the HTTPS URL
    /// returned by `gh`. Retained stale data stays visible with a marker.
    @ViewBuilder
    private func pullRequestsSection(_ snapshot: RepoSnapshot) -> some View {
        if showsPullRequests(snapshot) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(L10n.t("Pull requests", "Pull requests"))
                        .font(.caption.weight(.semibold))
                    if snapshot.pr.freshness == .stale {
                        Text(L10n.t("· datos antiguos", "· stale data"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(snapshot.pr.prs, id: \.number) { pr in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(pr.ciFailing ? Color.red : Color.green)
                            .frame(width: 6, height: 6)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PR #\(pr.number) · \(pr.title)")
                                .font(.caption)
                                .lineLimit(1)
                            Text(L10n.t("abierta \(pr.ageDays) \(pr.ageDays == 1 ? "día" : "días")\(pr.ciFailing ? " · checks fallidos" : "")",
                                        "open \(pr.ageDays) day\(pr.ageDays == 1 ? "" : "s")\(pr.ciFailing ? " · failing checks" : "")"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        if let url = pr.webURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(L10n.t("Abrir", "Open"), systemImage: "safari")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help(L10n.t("Abrir la PR en el navegador", "Open the pull request in the browser"))
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Retained stale PR data stays visible (a failed refresh never erases the
    /// last good value); only an unavailable source with no data shows nothing.
    private func showsPullRequests(_ snapshot: RepoSnapshot) -> Bool {
        snapshot.pr.freshness != .unavailable && !snapshot.pr.prs.isEmpty
    }

    private func checkoutSection(_ snapshot: RepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("Checkout principal · \(primaryBranchLabel(snapshot))", "Primary checkout · \(primaryBranchLabel(snapshot))"))
                .font(.caption.weight(.semibold))
            Text(changeSummary(snapshot.git.changes))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if snapshot.git.unpushedCount > 0 {
                Text(L10n.t("\(snapshot.git.unpushedCount) commit\(snapshot.git.unpushedCount == 1 ? "" : "s") sin subir", "\(snapshot.git.unpushedCount) unpushed commit\(snapshot.git.unpushedCount == 1 ? "" : "s")"))
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
                Text(L10n.t("Worktrees no disponibles", "Worktrees unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if all.isEmpty {
                Text(L10n.t("Sin worktrees adicionales", "No additional worktrees"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.t("Worktrees", "Worktrees"))
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
                            Text(state.showCleanWorktrees
                                ? L10n.t("Ocultar \(clean.count) worktree\(clean.count == 1 ? "" : "s") limpio\(clean.count == 1 ? "" : "s")", "Hide \(clean.count) clean worktree\(clean.count == 1 ? "" : "s")")
                                : L10n.t("Ver \(clean.count) worktree\(clean.count == 1 ? "" : "s") limpio\(clean.count == 1 ? "" : "s")", "Show \(clean.count) clean worktree\(clean.count == 1 ? "" : "s")"))
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
        return snapshot.git.freshness == .unavailable ? L10n.t("no disponible", "unavailable") : "detached"
    }

    private func changeSummary(_ changes: ChangeCounts) -> String {
        var parts = [
            "Staged \(changes.staged)",
            "Unstaged \(changes.unstaged)",
            "Untracked \(changes.untracked)"
        ]
        if changes.conflicts > 0 {
            parts.append("\(L10n.t("Conflictos", "Conflicts")) \(changes.conflicts)")
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
