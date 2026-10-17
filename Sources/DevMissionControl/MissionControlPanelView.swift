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
/// window (S16/S17).
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
                            sectionTitle("Necesitan atención")
                            ForEach(appState.attentionOrder, id: \.config.path) { snapshot in
                                ProjectCard(appState: appState, snapshot: snapshot) { focus in
                                    onOpenDetail(snapshot.config.path, focus)
                                }
                            }
                        }
                        if ui.filter == .all, !appState.cleanOrder.isEmpty {
                            sectionTitle("Otros proyectos")
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
                Picker("Proyectos", selection: $ui.filter) {
                    Text("Atención").tag(PanelProjectFilter.attention)
                    Text("Todos").tag(PanelProjectFilter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
                .accessibilityLabel("Filtro de proyectos")
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
        let projects = summary.affectedProjects == 1 ? "proyecto" : "proyectos"
        let notices = summary.notices == 1 ? "aviso" : "avisos"
        return "\(summary.affectedProjects) \(projects) · \(summary.notices) \(notices)"
    }

    private var lastRefreshLabel: String {
        guard let last = appState.lastRefresh else { return "sin escaneos" }
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
            .help("Escanear todos los proyectos")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.config.repos.isEmpty ? "No hay proyectos seguidos" : "Escaneando…")
                .font(.headline)
            if appState.config.repos.isEmpty {
                Text("Agregá repositorios para ver PRs, CI, worktrees\ny la última actividad del agente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Abrir ajustes", action: onOpenSettings)
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
            Button("Ajustes", action: onOpenSettings)
                .controlSize(.small)
            Button("Salir", action: onQuit)
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
                Text("Principal ·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(primaryBranchLabel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 4)
                if snapshot.config.isPaused {
                    Label("Pausado", systemImage: "pause.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(items.count) \(items.count == 1 ? "aviso" : "avisos")")
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
        .accessibilityLabel("Proyecto \(snapshot.config.id)")
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
            .accessibilityLabel("Abrir detalle: \(first.message)")
        } else {
            Text(primaryReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var primaryBranchLabel: String {
        if let branch = snapshot.git.branch { return branch }
        return snapshot.git.freshness == .unavailable ? "no disponible" : "detached"
    }

    private var worktreeCountLabel: String {
        guard snapshot.git.freshness != .unavailable else { return "worktrees no disponibles" }
        let count = snapshot.git.worktrees.count
        return "\(count) worktree\(count == 1 ? "" : "s")"
    }

    private var primaryReason: String {
        if let reason = items.first?.message { return reason }
        let sourcesCurrent = snapshot.git.freshness == .current
            && snapshot.pr.freshness == .current
            && snapshot.activity.freshness == .current
        return sourcesCurrent ? "Sin hallazgos actuales" : "Sin hallazgos actuales · datos incompletos"
    }

    private func color(for severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

/// Per-source freshness badges with exact read times. For Engram the
/// connection state is shown separately from the latest saved session
/// summary (S19).
struct SourceFreshnessRow: View {
    let snapshot: RepoSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            SourceFreshnessBadge(source: "Git", freshness: snapshot.git.freshness,
                                 lastReadAt: snapshot.git.lastReadAt, error: snapshot.git.error)
            SourceFreshnessBadge(source: "GitHub", freshness: snapshot.pr.freshness,
                                 lastReadAt: snapshot.pr.lastReadAt, error: snapshot.pr.error)
            SourceFreshnessBadge(source: "Engram", freshness: snapshot.activity.freshness,
                                 lastReadAt: snapshot.activity.lastReadAt,
                                 error: snapshot.activity.error,
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

    /// S19: the connection state is explicit; Engram's current read never
    /// claims the memory matches the code.
    private var stateText: String {
        switch freshness {
        case .current:
            return source == "Engram" ? "Conectado" : "actual"
        case .stale:
            return "antiguo"
        case .unavailable:
            return source == "Engram" ? "Sin conexión" : "no disponible"
        }
    }

    private var readTimeText: String {
        lastReadAt?.formatted(date: .omitted, time: .shortened) ?? "sin lectura"
    }

    private var summaryLine: String? {
        guard source == "Engram" else { return nil }
        guard let savedSummary else {
            return freshness == .current ? "Sin resumen guardado" : nil
        }
        return "Resumen guardado · \(savedSummary.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var helpText: String {
        var parts = ["\(source): \(stateText)"]
        if freshness == .current {
            parts.append("consultado \(readTimeText)")
        } else if let lastReadAt {
            parts.append("última lectura \(lastReadAt.formatted(date: .abbreviated, time: .standard))")
        } else {
            parts.append("sin lecturas exitosas")
        }
        if let savedSummary {
            parts.append("último resumen guardado \(savedSummary.date.formatted(date: .abbreviated, time: .standard))")
        } else if source == "Engram", freshness == .current {
            parts.append("sin resumen guardado en las últimas observaciones")
        }
        if let error { parts.append("error actual: \(error)") }
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
                        Label("Abrir en editor", systemImage: "square.and.pencil")
                    }
                } else {
                    Button {
                        onConfigureEditor()
                    } label: {
                        Label("Configurar editor…", systemImage: "gearshape")
                    }
                }

                Button {
                    openTerminal()
                } label: {
                    Label("Abrir en Terminal", systemImage: "terminal")
                }

                Button {
                    showDiff()
                } label: {
                    Label(actionState.isLoadingDiff ? "Preparando diff…" : "Ver diff",
                          systemImage: "doc.text.magnifyingglass")
                }
                .disabled(actionState.isLoadingDiff)

                if let pullRequest {
                    Button {
                        openPullRequest(pullRequest)
                    } label: {
                        Label("Abrir PR #\(pullRequest.number)",
                              systemImage: "arrow.up.right.square")
                    }
                }

                Divider()
                Button(action: revealInFinder) {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
                Button(action: copyPath) {
                    Label("Copiar ruta", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Acciones para \(worktree.name)")
            .accessibilityLabel("Acciones para \(worktree.name)")
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
        .alert("Falló la acción del worktree", isPresented: Binding(
            get: { actionState.actionError != nil },
            set: { if !$0 { actionState.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionState.actionError = nil }
        } message: {
            Text(actionState.actionError ?? "Error desconocido")
        }
    }

    /// Last-commit age stays informational; it is neither the local
    /// modification time nor agent activity (S19).
    private var statusSummary: String {
        let commitAge: String
        if worktree.lastCommitAt == nil {
            commitAge = "sin fecha de último commit"
        } else if worktree.ageDays == 0 {
            commitAge = "último commit hoy"
        } else {
            commitAge = "último commit hace \(worktree.ageDays) \(worktree.ageDays == 1 ? "día" : "días")"
        }

        var parts = [
            "Staged \(worktree.changes.staged)",
            "Unstaged \(worktree.changes.unstaged)",
            "Untracked \(worktree.changes.untracked)"
        ]
        if worktree.changes.conflicts > 0 {
            parts.append("Conflictos \(worktree.changes.conflicts)")
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
            actionState.actionError = "Configurá un editor en Ajustes."
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
            actionState.actionError = "Esta PR no tiene URL HTTPS segura."
            return
        }
        if !NSWorkspace.shared.open(url) {
            actionState.actionError = "No se pudo abrir la PR #\(pullRequest.number)."
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
                Button("Cerrar") { dismiss() }
            }
            Divider()
            if diff.isEmpty {
                Text("No hay cambios tracked respecto a HEAD. Los archivos untracked no se incluyen.")
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
