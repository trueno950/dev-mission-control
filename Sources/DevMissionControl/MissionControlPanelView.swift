import AppKit
import SwiftUI
import DevControlCore

/// Visible panel filter: attention first, or every tracked project (S17).
enum PanelProjectFilter: Hashable {
    case attention
    case all
}

/// Local UI state for the panel. Held in an ObservableObject because this
/// Command Line Tools environment cannot load the `@State` macro.
@MainActor
final class PanelUIState: ObservableObject {
    @Published var filter: PanelProjectFilter = .attention
}

/// Root view of the status panel: attention first, with a visible
/// Atención/Todos selector and compact cards that open a repository detail
/// window (S16/S17). All copy follows the system language.
struct MissionControlPanelView: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void
    let onOpenDetail: (_ repoPath: String, _ focusWorktreePath: String?) -> Void
    let onQuit: () -> Void
    @StateObject private var ui = PanelUIState()

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
                            sectionTitle(L10n.t("Necesitan atención", "Needs attention"))
                            ForEach(appState.attentionOrder, id: \.config.path) { snapshot in
                                ProjectCard(appState: appState, snapshot: snapshot) { focus in
                                    onOpenDetail(snapshot.config.path, focus)
                                }
                            }
                        }
                        if ui.filter == .all, !appState.cleanOrder.isEmpty {
                            sectionTitle(L10n.t("Otros proyectos", "Other projects"))
                            ForEach(appState.cleanOrder, id: \.config.path) { snapshot in
                                ProjectCard(appState: appState, snapshot: snapshot) { focus in
                                    onOpenDetail(snapshot.config.path, focus)
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
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
    }

    // MARK: - Pieces

    /// Visible access to every tracked project, clean or paused (S17).
    @ViewBuilder private var filterBar: some View {
        if !appState.snapshots.isEmpty, !appState.cleanOrder.isEmpty {
            HStack {
                Picker(L10n.t("Proyectos", "Projects"), selection: $ui.filter) {
                    Text(L10n.t("Atención", "Attention")).tag(PanelProjectFilter.attention)
                    Text(L10n.t("Todos", "All")).tag(PanelProjectFilter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
                .accessibilityLabel(L10n.t("Filtro de proyectos", "Project filter"))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.15))
        }
    }

    private var header: some View {
        let summary = appState.attentionSummary
        return HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.gradient)
            Text("Mission Control")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(summaryLabel(summary))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.affectedProjects == 0 ? Color.secondary : Color.orange)
                Text(lastRefreshLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            refreshButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func summaryLabel(_ summary: AttentionSummary) -> String {
        let projects = L10n.t(summary.affectedProjects == 1 ? "proyecto" : "proyectos",
                              summary.affectedProjects == 1 ? "project" : "projects")
        let notices = L10n.t(summary.notices == 1 ? "aviso" : "avisos",
                             summary.notices == 1 ? "notice" : "notices")
        return "\(summary.affectedProjects) \(projects) · \(summary.notices) \(notices)"
    }

    private var lastRefreshLabel: String {
        guard let last = appState.lastRefresh else { return L10n.t("sin escaneos", "never scanned") }
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
            .help(L10n.t("Escanear todos los proyectos", "Scan all projects"))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.config.repos.isEmpty
                 ? L10n.t("No hay proyectos seguidos", "No projects tracked yet")
                 : L10n.t("Escaneando…", "Scanning…"))
                .font(.headline)
            if appState.config.repos.isEmpty {
                Text(L10n.t("Agregá repositorios para ver PRs, CI, worktrees\ny la última actividad del agente.",
                            "Add repositories to see PRs, CI, worktrees\nand last agent activity."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.t("Abrir ajustes", "Open Settings"), action: onOpenSettings)
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
            Button(L10n.t("Ajustes", "Settings"), action: onOpenSettings)
                .controlSize(.small)
            Button(L10n.t("Salir", "Quit"), action: onQuit)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Compact repository summary. Clicking the card opens the repository detail
/// window; clicking the primary notice focuses that notice's worktree (S17).
struct ProjectCard: View {
    @ObservedObject var appState: AppState
    let snapshot: RepoSnapshot
    let onOpenDetail: (_ focusWorktreePath: String?) -> Void

    private var items: [AttentionItem] { appState.items(for: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(snapshot.config.id)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(worktreeCountLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(L10n.t("Principal ·", "Primary ·"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(primaryBranchLabel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 4)
                if snapshot.config.isPaused {
                    Label(L10n.t("Pausado", "Paused"), systemImage: "pause.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(noticeCountLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(items.isEmpty ? Color.secondary : Color.primary)
            }
            primaryNoticeRow
            SourceFreshnessRow(snapshot: snapshot)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail(nil) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Proyecto \(snapshot.config.id)", "Project \(snapshot.config.id)"))
    }

    /// The primary notice doubles as the direct shortcut to the problem.
    @ViewBuilder private var primaryNoticeRow: some View {
        if let first = items.first {
            Button {
                onOpenDetail(first.worktreePath)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(color(for: first.severity))
                        .frame(width: 6, height: 6)
                    Text(first.message)
                        .font(.caption)
                        .foregroundStyle(first.severity == .info ? Color.secondary : .primary)
                        .lineLimit(1)
                    if items.count > 1 {
                        Text("+\(items.count - 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Abrir detalle: \(first.message)",
                                       "Open detail: \(first.message)"))
        } else {
            Text(primaryReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var noticeCountLabel: String {
        let noun = L10n.t(items.count == 1 ? "aviso" : "avisos",
                          items.count == 1 ? "notice" : "notices")
        return "\(items.count) \(noun)"
    }

    private var primaryBranchLabel: String {
        if let branch = snapshot.git.branch { return branch }
        return snapshot.git.freshness == .unavailable
            ? L10n.t("no disponible", "unavailable")
            : "detached"
    }

    private var worktreeCountLabel: String {
        guard snapshot.git.freshness != .unavailable else {
            return L10n.t("worktrees no disponibles", "worktrees unavailable")
        }
        let count = snapshot.git.worktrees.count
        return "\(count) worktree\(count == 1 ? "" : "s")"
    }

    private var primaryReason: String {
        if let reason = items.first?.message { return reason }
        let sourcesCurrent = snapshot.git.freshness == .current
            && snapshot.pr.freshness == .current
            && snapshot.activity.freshness == .current
        return sourcesCurrent
            ? L10n.t("Sin hallazgos actuales", "No current findings")
            : L10n.t("Sin hallazgos actuales · datos incompletos",
                     "No current findings · incomplete source data")
    }

    private func color(for severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

/// Per-source freshness badges with visible read times and relevant data:
/// GitHub shows its open-PR count and Engram shows its latest activity plus
/// saved session summary. Connection state stays separate from memory
/// freshness (S19).
struct SourceFreshnessRow: View {
    let snapshot: RepoSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            SourceFreshnessBadge(source: "Git", freshness: snapshot.git.freshness,
                                 lastReadAt: snapshot.git.lastReadAt, error: snapshot.git.error)
            SourceFreshnessBadge(source: "GitHub", freshness: snapshot.pr.freshness,
                                 lastReadAt: snapshot.pr.lastReadAt, error: snapshot.pr.error,
                                 openPRCount: snapshot.pr.freshness == .current
                                     ? snapshot.pr.prs.count : nil)
            SourceFreshnessBadge(source: "Engram", freshness: snapshot.activity.freshness,
                                 lastReadAt: snapshot.activity.lastReadAt,
                                 error: snapshot.activity.error,
                                 lastActivity: snapshot.activity.activity,
                                 savedSummary: snapshot.activity.summary)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SourceFreshnessBadge: View {
    let source: String
    let freshness: SourceFreshness
    let lastReadAt: Date?
    let error: String?
    var openPRCount: Int?
    var lastActivity: ActivityInfo?
    var savedSummary: SessionSummaryInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(source)
                    .font(.system(size: 9, weight: .semibold))
                Text(stateText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if let pullRequestLine {
                Text(pullRequestLine)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let activityLine {
                Text(activityLine)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let summaryLine {
                Text(summaryLine)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
    }

    private var statusColor: Color {
        switch freshness {
        case .current: return .green
        case .stale: return .orange
        case .unavailable: return .secondary
        }
    }

    /// S19: the connection state is explicit and carries the visible read
    /// time; Engram's current read never claims the memory matches the code.
    private var stateText: String {
        switch freshness {
        case .current:
            let base = source == "Engram" ? L10n.t("Conectado", "Connected") : L10n.t("actual", "current")
            return "\(base) · \(shortReadTime)"
        case .stale:
            return "\(L10n.t("antiguo", "stale")) · \(shortReadTime)"
        case .unavailable:
            return source == "Engram" ? L10n.t("Sin conexión", "No connection") : L10n.t("no disponible", "unavailable")
        }
    }

    private var shortReadTime: String {
        lastReadAt?.formatted(date: .omitted, time: .shortened) ?? L10n.t("sin lectura", "no read")
    }

    private var pullRequestLine: String? {
        guard source == "GitHub", freshness == .current, let openPRCount else { return nil }
        if openPRCount == 0 { return L10n.t("Sin PRs abiertas", "No open PRs") }
        return L10n.t("\(openPRCount) PR\(openPRCount == 1 ? "" : "s") abierta\(openPRCount == 1 ? "" : "s")",
                      "\(openPRCount) open PR\(openPRCount == 1 ? "" : "s")")
    }

    private var activityLine: String? {
        guard source == "Engram", let lastActivity else { return nil }
        return "\(L10n.t("Actividad", "Activity")) · \(lastActivity.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var summaryLine: String? {
        guard source == "Engram" else { return nil }
        guard let savedSummary else {
            return freshness == .current ? L10n.t("Sin resumen guardado", "No saved summary") : nil
        }
        return "\(L10n.t("Resumen guardado", "Saved summary")) · \(savedSummary.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var helpText: String {
        var parts = ["\(source): \(stateText)"]
        if let lastReadAt {
            parts.append("\(L10n.t("última lectura", "last read")) \(lastReadAt.formatted(date: .abbreviated, time: .standard))")
        } else {
            parts.append(L10n.t("sin lecturas exitosas", "no successful reads"))
        }
        if let openPRCount {
            parts.append(L10n.t("\(openPRCount) PRs abiertas", "\(openPRCount) open PRs"))
        }
        if let lastActivity {
            parts.append("\(L10n.t("última actividad", "last activity")): \(lastActivity.title)")
        }
        if let savedSummary {
            parts.append("\(L10n.t("último resumen guardado", "last saved summary")) \(savedSummary.date.formatted(date: .abbreviated, time: .standard))")
        } else if source == "Engram", freshness == .current {
            parts.append(L10n.t("sin resumen guardado en las últimas observaciones",
                                "no saved summary in the recent observations"))
        }
        if let error { parts.append("\(L10n.t("error actual", "current error")): \(error)") }
        return parts.joined(separator: " · ")
    }
}

/// Local UI state for one worktree's asynchronous actions.
@MainActor
final class WorktreeActionState: ObservableObject {
    @Published var isLoadingDiff = false
    @Published var showingDiff = false
    @Published var diffText = ""
    @Published var actionError: String?
}

/// Detailed, read-only triage row for a linked worktree. When `isFocused`,
/// the row is highlighted because a notice led here (S17).
struct WorktreeTriageRow: View {
    let worktree: WorktreeInfo
    let severity: AttentionItem.Severity
    let editorApplicationPath: String?
    let pullRequest: PRInfo?
    var isFocused: Bool = false
    let onConfigureEditor: () -> Void
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
                if editorApplicationPath != nil {
                    Button {
                        openEditor()
                    } label: {
                        Label(L10n.t("Abrir en editor", "Open in Editor"),
                              systemImage: "square.and.pencil")
                    }
                } else {
                    Button {
                        onConfigureEditor()
                    } label: {
                        Label(L10n.t("Configurar editor…", "Set up Editor…"),
                              systemImage: "gearshape")
                    }
                }

                Button {
                    openTerminal()
                } label: {
                    Label(L10n.t("Abrir en Terminal", "Open in Terminal"),
                          systemImage: "terminal")
                }

                Button {
                    showDiff()
                } label: {
                    Label(actionState.isLoadingDiff
                          ? L10n.t("Preparando diff…", "Preparing Diff…")
                          : L10n.t("Ver diff", "Show Diff"),
                          systemImage: "doc.text.magnifyingglass")
                }
                .disabled(actionState.isLoadingDiff)

                if let pullRequest {
                    Button {
                        openPullRequest(pullRequest)
                    } label: {
                        Label(L10n.t("Abrir PR #\(pullRequest.number)",
                                     "Open PR #\(pullRequest.number)"),
                              systemImage: "arrow.up.right.square")
                    }
                }

                Divider()
                Button(action: revealInFinder) {
                    Label(L10n.t("Mostrar en Finder", "Reveal in Finder"),
                          systemImage: "folder")
                }
                Button(action: copyPath) {
                    Label(L10n.t("Copiar ruta", "Copy Path"), systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L10n.t("Acciones para \(worktree.name)", "Actions for \(worktree.name)"))
            .accessibilityLabel(L10n.t("Acciones para \(worktree.name)",
                                       "Actions for \(worktree.name)"))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, isFocused ? 6 : 0)
        .background {
            if isFocused {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
            }
        }
        .sheet(isPresented: $actionState.showingDiff) {
            WorktreeDiffSheet(worktreeName: worktree.name, diff: actionState.diffText)
        }
        .alert(L10n.t("Falló la acción del worktree", "Worktree Action Failed"),
               isPresented: Binding(
            get: { actionState.actionError != nil },
            set: { if !$0 { actionState.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionState.actionError = nil }
        } message: {
            Text(actionState.actionError ?? L10n.t("Error desconocido", "Unknown error"))
        }
    }

    /// Last-commit age stays informational; it is neither the local
    /// modification time nor agent activity (S19).
    private var statusSummary: String {
        let commitAge: String
        if worktree.lastCommitAt == nil {
            commitAge = L10n.t("sin fecha de último commit", "no last-commit date")
        } else if worktree.ageDays == 0 {
            commitAge = L10n.t("último commit hoy", "last commit today")
        } else {
            commitAge = L10n.t("último commit hace \(worktree.ageDays) \(worktree.ageDays == 1 ? "día" : "días")",
                               "last commit \(worktree.ageDays) day\(worktree.ageDays == 1 ? "" : "s") ago")
        }

        var parts = [
            "Staged \(worktree.changes.staged)",
            "Unstaged \(worktree.changes.unstaged)",
            "Untracked \(worktree.changes.untracked)"
        ]
        if worktree.changes.conflicts > 0 {
            parts.append("\(L10n.t("Conflictos", "Conflicts")) \(worktree.changes.conflicts)")
        }
        parts.append(commitAge)
        return parts.joined(separator: " · ")
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
            actionState.actionError = L10n.t("Configurá un editor en Ajustes.",
                                             "Set up an editor in Settings first.")
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
            actionState.actionError = L10n.t("Esta PR no tiene URL HTTPS segura.",
                                             "This pull request has no safe HTTPS URL.")
            return
        }
        if !NSWorkspace.shared.open(url) {
            actionState.actionError = L10n.t("No se pudo abrir la PR #\(pullRequest.number).",
                                             "Could not open pull request #\(pullRequest.number).")
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
                Button(L10n.t("Cerrar", "Done")) { dismiss() }
            }
            Divider()
            if diff.isEmpty {
                Text(L10n.t("No hay cambios tracked respecto a HEAD. Los archivos untracked no se incluyen.",
                            "No tracked changes relative to HEAD. Untracked files are not included."))
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
