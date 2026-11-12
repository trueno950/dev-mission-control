import AppKit
import SwiftUI
import DevControlCore

/// Local UI state for one worktree's asynchronous actions.
@MainActor
final class WorktreeActionState: ObservableObject {
    @Published var isLoadingDiff = false
    @Published var showingDiff = false
    @Published var diffText = ""
    @Published var actionError: String?
}

/// Local UI state of the worktrees section: the clean-worktree disclosure and
/// the transient copy confirmation. Held in an ObservableObject because this
/// environment cannot load the `@State` macro.
@MainActor
final class WorktreesSectionUI: ObservableObject {
    @Published var showsCleanWorktrees = false
    @Published var copiedCommand = false
    private var copiedTask: Task<Void, Never>?

    /// Shows "Copied" next to the button and clears it shortly after (S6).
    func showCopied() {
        copiedCommand = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copiedCommand = false
        }
    }
}

/// "Worktrees" section of the split console detail (S6): the primary checkout,
/// the linked worktrees that need a look, and one grouped block for the clean
/// idle ones. A state pill always names the state with a shape-free text label
/// and never renders a zero counter.
struct WorktreesSection: View {
    @ObservedObject var appState: AppState
    let snapshot: RepoSnapshot
    let now: Date
    let onOpenSettings: () -> Void
    @StateObject private var ui = WorktreesSectionUI()

    private var ordered: [WorktreeInfo] {
        WorktreeOrdering.sortedForTriage(snapshot.git.worktrees)
    }

    private var active: [WorktreeInfo] { ordered.filter { WorktreeOrdering.rank($0) < 2 } }
    private var clean: [WorktreeInfo] { ordered.filter { WorktreeOrdering.rank($0) == 2 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleSectionHeader(title: L10n.t("Worktrees", "Worktrees"))
            if snapshot.git.freshness == .unavailable {
                unavailableBox
            } else {
                table
                if !clean.isEmpty {
                    cleanBlock
                    disclosure
                }
            }
        }
    }

    // MARK: - Table

    /// Column widths shared by the header and every row: the worktree column
    /// flexes, the state pill and the right-aligned age stay fixed so the
    /// "Last commit" column reads as tabular digits.
    private let stateColumnWidth: CGFloat = 96
    private let commitColumnWidth: CGFloat = 76
    private let actionColumnWidth: CGFloat = 18

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().opacity(0.25)
            primaryRow
            ForEach(active, id: \.path) { worktree in
                Divider().opacity(0.25)
                linkedRow(worktree)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(L10n.t("Worktree", "Worktree"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.t("Estado", "State"))
                .frame(width: stateColumnWidth, alignment: .leading)
            Text(L10n.t("Último commit", "Last commit"))
                .frame(width: commitColumnWidth, alignment: .trailing)
            Color.clear
                .frame(width: actionColumnWidth, height: 1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    /// The primary checkout is the first row and is never part of the cleanup
    /// group (S6). It has no per-worktree actions menu: the header owns them.
    private var primaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            nameCell(name: snapshot.git.branch ?? detachedLabel,
                     sub: L10n.t("checkout principal", "primary checkout"),
                     subMonospaced: false)
            WorktreeStatePillView(
                state: ConsoleWorktreeSummary.state(
                    WorktreeInfo(path: snapshot.config.path,
                                 name: snapshot.config.id,
                                 isDirty: snapshot.git.changes.isDirty,
                                 ageDays: 0,
                                 changes: snapshot.git.changes),
                    language: L10n.lang),
                breakdown: ConsoleWorktreeSummary.breakdown(snapshot.git.changes))
                .frame(width: stateColumnWidth, alignment: .leading)
            commitAgeText(snapshot.git.lastCommit?.date)
                .frame(width: commitColumnWidth, alignment: .trailing)
            Color.clear
                .frame(width: actionColumnWidth, height: 1)
        }
        .padding(.vertical, 7)
    }

    private func linkedRow(_ worktree: WorktreeInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            nameCell(name: worktree.name, sub: worktree.branch ?? detachedLabel)
            WorktreeStatePillView(state: ConsoleWorktreeSummary.state(worktree,
                                                                     language: L10n.lang),
                                  breakdown: ConsoleWorktreeSummary.breakdown(worktree.changes))
                .frame(width: stateColumnWidth, alignment: .leading)
            commitAgeText(worktree.lastCommitAt)
                .frame(width: commitColumnWidth, alignment: .trailing)
            WorktreeActionMenu(worktree: worktree,
                               editorApplicationPath: appState.config.editorApplicationPath,
                               pullRequest: snapshot.associatedPullRequest(for: worktree),
                               onConfigureEditor: onOpenSettings)
                .frame(width: actionColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private func nameCell(name: String, sub: String, subMonospaced: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(sub)
                .font(.system(size: 11, design: subMonospaced ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Right-aligned, tabular age; a worktree without a commit date says so.
    private func commitAgeText(_ date: Date?) -> some View {
        Text(date.map { RelativeAge.short(from: $0, to: now, language: L10n.lang) }
             ?? L10n.t("sin fecha", "no date"))
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Clean group (S6)

    private var cleanCommonFolder: String? {
        WorktreeCleanup.commonFolder(repoPath: snapshot.config.path,
                                     worktreePaths: clean.map { $0.path })
    }

    /// The ignored folder holding every clean worktree, when there is one.
    private var ignoredFolder: String? {
        guard let folder = cleanCommonFolder,
              snapshot.config.ignoredWorktreeFolders.contains(folder),
              clean.allSatisfy({ snapshot.config.ignoresWorktree(at: $0.path) }) else {
            return nil
        }
        return folder
    }

    private var cleanBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ConsoleWorktreeSummary.cleanHeadline(clean, language: L10n.lang))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(cleanNamesLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                copyCleanupButton
                if let ignoredFolder {
                    Text(L10n.t("Carpeta ignorada", "Folder ignored"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(L10n.t("Dejar de ignorar", "Stop ignoring")) {
                        appState.setIgnoredWorktreeFolder(repoPath: snapshot.config.path,
                                                          folder: ignoredFolder,
                                                          ignored: false)
                    }
                    .controlSize(.small)
                    .help(L10n.t("Vuelve a avisar de estos worktrees inactivos",
                                 "Warn about these idle worktrees again"))
                } else if let folder = WorktreeCleanup.ignorableFolder(
                    repoPath: snapshot.config.path,
                    cleanPaths: clean.map { $0.path },
                    activePaths: active.map { $0.path }) {
                    Button(L10n.t("Ignorar esta carpeta", "Ignore this folder")) {
                        appState.setIgnoredWorktreeFolder(repoPath: snapshot.config.path,
                                                          folder: folder,
                                                          ignored: true)
                    }
                    .controlSize(.small)
                    .help(L10n.t("Deja de avisar de los worktrees inactivos de \(folder)/",
                                 "Stop warning about idle worktrees inside \(folder)/"))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .accessibilityElement(children: .contain)
    }

    private var copyCleanupButton: some View {
        HStack(spacing: 6) {
            Button(L10n.t("Copiar comando de limpieza", "Copy cleanup command")) {
                let command = WorktreeCleanup.command(repoPath: snapshot.config.path,
                                                      worktreePaths: clean.map { $0.path })
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                ui.showCopied()
            }
            .controlSize(.small)
            .help(L10n.t("Copia los comandos git worktree remove para pegar en una terminal. No se ejecutan aquí.",
                         "Copies the git worktree remove commands to paste in a terminal. Nothing runs here."))
            if ui.copiedCommand {
                Text(L10n.t("Copiado", "Copied"))
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    /// "<commonFolder>/ · name1, name2, …"; the folder part appears only when
    /// every clean worktree shares one repository-relative folder.
    private var cleanNamesLine: String {
        let names = clean.map { $0.name }.joined(separator: ", ")
        guard let folder = cleanCommonFolder else { return names }
        return "\(folder)/ · \(names)"
    }

    private var disclosure: some View {
        DisclosureGroup(isExpanded: $ui.showsCleanWorktrees) {
            VStack(spacing: 0) {
                ForEach(clean, id: \.path) { worktree in
                    linkedRow(worktree)
                    if worktree.path != clean.last?.path {
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(L10n.t("Ver worktrees limpios", "Show clean worktrees"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(L10n.t("Ver worktrees limpios", "Show clean worktrees"))
    }

    /// S5: an unavailable Git read is never an empty table.
    private var unavailableBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("Worktrees no disponibles", "Worktrees unavailable"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let error = snapshot.git.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detachedLabel: String {
        snapshot.git.freshness == .unavailable
            ? L10n.t("no disponible", "unavailable")
            : "detached"
    }
}

/// State pill of one worktree row (S6): conflicts red, pending orange, clean
/// gray. The text carries the information; the color only reinforces it.
struct WorktreeStatePillView: View {
    let state: ConsoleWorktreeState
    /// Prior S7/S10: non-zero staged/unstaged/untracked counts, one per line.
    var breakdown: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.text)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(color.opacity(0.13), in: Capsule())
            ForEach(breakdown, id: \.self) { line in
                Text(line)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state.kind {
        case .conflicts: return .red
        case .pending: return .orange
        case .clean: return .secondary
        }
    }
}

/// Per-worktree actions menu, carried over from the repository detail window:
/// editor, Terminal, diff, the associated PR, Finder and copy path. The action
/// logic is unchanged: `WorktreeActionCommand` + `ProcessRunner` off the main
/// actor.
struct WorktreeActionMenu: View {
    let worktree: WorktreeInfo
    let editorApplicationPath: String?
    let pullRequest: PRInfo?
    let onConfigureEditor: () -> Void
    @StateObject private var actionState = WorktreeActionState()

    var body: some View {
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

    // MARK: - Actions

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

/// Diff sheet of one worktree; kept from the repository detail window.
struct WorktreeDiffSheet: View {
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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(DiffParser.parse(diff)) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowBackground(for: line.kind))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }

    /// S20: additions render green, removals red; metadata dims and hunk
    /// headers use the accent color.
    private func color(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return .green
        case .removal: return .red
        case .hunkHeader: return .accentColor
        case .meta: return .secondary
        case .context: return .primary
        }
    }

    private func rowBackground(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .removal: return Color.red.opacity(0.12)
        default: return .clear
        }
    }
}
