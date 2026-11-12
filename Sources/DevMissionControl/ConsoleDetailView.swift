import AppKit
import SwiftUI
import DevControlCore

/// Section header of the detail pane (S2): caption2, semibold, uppercase and
/// secondary, on the 8/12/16 spacing rhythm.
struct ConsoleSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Local UI state of the detail pane: the transient copy confirmations and the
/// last action error. Held in an ObservableObject because this environment
/// cannot load the `@State` macro.
@MainActor
final class ConsoleDetailUI: ObservableObject {
    @Published var copyConfirmation: String?
    @Published var isCopyingContext = false
    @Published var authCommandCopied = false
    @Published var actionError: String?
    private var confirmationTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?

    /// Shows the copy confirmation returned by the Engram panel and clears it
    /// shortly after (S5).
    func showCopyConfirmation(_ text: String?) {
        copyConfirmation = text
        confirmationTask?.cancel()
        guard text != nil else { return }
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.copyConfirmation = nil
        }
    }

    /// Shows "Copied" next to the `gh auth login` button, then clears it (S7).
    func showAuthCommandCopied() {
        authCommandCopied = true
        authTask?.cancel()
        authTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.authCommandCopied = false
        }
    }
}

/// Right-hand pane of the split console (S4-S7): the selected project's header
/// with its actions, "Where you left off", worktrees, pull requests and one
/// freshness line per source. Everything is read-only.
struct ConsoleDetailView: View {
    @ObservedObject var appState: AppState
    let snapshot: RepoSnapshot
    let now: Date
    let onOpenSettings: () -> Void
    let onOpenEngramPanel: (String) -> Void
    let onCopyRetakeContext: @MainActor (String) async -> String?
    @StateObject private var ui = ConsoleDetailUI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                resumeSection
                WorktreesSection(appState: appState,
                                 snapshot: snapshot,
                                 now: now,
                                 onOpenSettings: onOpenSettings)
                pullRequestsSection
                sourcesLine
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(L10n.t("Falló la acción del proyecto", "Project Action Failed"),
               isPresented: Binding(
            get: { ui.actionError != nil },
            set: { if !$0 { ui.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { ui.actionError = nil }
        } message: {
            Text(ui.actionError ?? L10n.t("Error desconocido", "Unknown error"))
        }
    }

    // MARK: - Header (S4)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(snapshot.config.id)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if snapshot.config.isPaused {
                        Text(L10n.t("Pausado", "Paused"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.4), in: Capsule())
                    }
                }
                Text("\(branchLabel) · \(abbreviatedPath)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    openEditor()
                } label: {
                    Text(editorActionTitle)
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(editorHelp)
                .accessibilityLabel(editorActionTitle)

                Button {
                    openTerminal()
                } label: {
                    Text(L10n.t("Terminal", "Terminal"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("Abre el proyecto en Terminal",
                             "Opens the project in Terminal"))
                .accessibilityLabel(L10n.t("Abrir en Terminal", "Open in Terminal"))

                moreMenu
            }
            .fixedSize()
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                onOpenEngramPanel(snapshot.config.path)
            } label: {
                Label(L10n.t("Memorias de Engram", "Engram memories"),
                      systemImage: "text.book.closed")
            }
            Button {
                openEngramTUI()
            } label: {
                Label(L10n.t("TUI global de Engram", "Engram global TUI"),
                      systemImage: "terminal")
            }
            Divider()
            Button(action: revealInFinder) {
                Label(L10n.t("Mostrar en Finder", "Reveal in Finder"),
                      systemImage: "folder")
            }
            Button(action: copyPath) {
                Label(L10n.t("Copiar ruta", "Copy path"), systemImage: "doc.on.doc")
            }
        } label: {
            Text("•••")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("Más acciones", "More actions"))
        .accessibilityLabel(L10n.t("Más acciones", "More actions"))
    }

    // MARK: - Where you left off (S5)

    private var resumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleSectionHeader(title: L10n.t("Dónde te quedaste", "Where you left off"))
            VStack(alignment: .leading, spacing: 8) {
                activityBlock
                if let commit = snapshot.git.lastCommit {
                    commitLine(commit)
                }
                resumeActions
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// S5/L2: Engram stores no summary body, so the card shows the latest
    /// memory title and date — never invented prose. A missing activity is
    /// stated honestly and distinguished from a lost connection.
    @ViewBuilder private var activityBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let memory = snapshot.activity.activity {
                Text(memory.title)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(memoryMeta(memory))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    openMemoriesLink
                }
            } else {
                HStack(spacing: 6) {
                    Text(emptyActivityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    openMemoriesLink
                }
            }
        }
    }

    private var openMemoriesLink: some View {
        Button(L10n.t("Abrir memorias", "Open memories")) {
            onOpenEngramPanel(snapshot.config.path)
        }
        .buttonStyle(.link)
        .controlSize(.small)
        .help(L10n.t("Abre el panel de memorias de Engram de este proyecto",
                     "Opens this project's Engram memories panel"))
    }

    private func memoryMeta(_ memory: ActivityInfo) -> String {
        var text = "\(L10n.t("Memoria de Engram", "Engram memory")) · "
            + memory.date.formatted(date: .abbreviated, time: .shortened)
        if snapshot.activity.freshness == .stale {
            text += " · \(L10n.t("antiguo", "stale"))"
        }
        return text
    }

    private var emptyActivityText: String {
        snapshot.activity.freshness == .unavailable
            ? L10n.t("Engram sin conexión", "Engram not connected")
            : L10n.t("Sin memorias de Engram", "No Engram memories")
    }

    /// S5: hash, subject and a long relative age; omitted with no commit.
    private func commitLine(_ commit: LastCommitInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(commit.shortHash)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(commit.subject)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("· \(longAge(commit.date))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var resumeActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await copyContext() }
            } label: {
                Label(L10n.t("Copiar contexto para retomar", "Copy context to resume"),
                      systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(ui.isCopyingContext)
            .help(L10n.t("Lee /context de Engram y copia el bloque para retomar con el estado actual de Git. No escribe en Engram.",
                         "Reads Engram /context and copies the retake block with the current Git state. Writes nothing to Engram."))
            .accessibilityLabel(L10n.t("Copiar contexto para retomar", "Copy context to resume"))
            if ui.isCopyingContext {
                ProgressView()
                    .controlSize(.mini)
            } else if let confirmation = ui.copyConfirmation {
                Text(confirmation)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// S5: the same read and copy flow the Engram panel uses, through the
    /// window controller, so nothing is re-implemented here.
    private func copyContext() async {
        guard !ui.isCopyingContext else { return }
        ui.isCopyingContext = true
        let confirmation = await onCopyRetakeContext(snapshot.config.path)
        ui.isCopyingContext = false
        ui.showCopyConfirmation(confirmation)
    }

    // MARK: - Pull requests (S7)

    private var pullRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ConsoleSectionHeader(title: L10n.t("Pull requests", "Pull requests"))
                if snapshot.pr.freshness == .stale {
                    Text(L10n.t("· datos antiguos", "· stale data"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            if snapshot.pr.freshness == .unavailable {
                notReadBox
            } else if snapshot.pr.prs.isEmpty {
                Text(L10n.t("Sin PRs abiertas", "No open PRs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.pr.prs, id: \.number) { pullRequestRow($0) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func pullRequestRow(_ pullRequest: PRInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(pullRequest.ciFailing ? Color.red : Color.green)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("PR #\(pullRequest.number) · \(pullRequest.title)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(pullRequestAgeLine(pullRequest))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url = pullRequest.webURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(L10n.t("Abrir", "Open"), systemImage: "safari")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(L10n.t("Abrir la PR en el navegador",
                             "Open the pull request in the browser"))
            }
        }
    }

    private func pullRequestAgeLine(_ pullRequest: PRInfo) -> String {
        let days = pullRequest.ageDays
        return L10n.t("abierta \(days) \(AppLanguage.plural(days, "día", "días"))\(pullRequest.ciFailing ? " · checks fallidos" : "")",
                      "open \(days) \(AppLanguage.plural(days, "day", "days"))\(pullRequest.ciFailing ? " · failing checks" : "")")
    }

    /// S7/L2: GitHub unread is stated as unknown, never as zero open PRs. The
    /// login command is offered only for an authentication error.
    private var notReadBox: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("No leído.", "Not read."))
                    .font(.system(size: 12, weight: .semibold))
                if let error = snapshot.pr.error {
                    Text(L10n.t("PRs abiertas y CI desconocidos, no cero.",
                                "Open PRs and CI are unknown — not zero."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("No se encontró un remoto de GitHub para este repositorio.",
                                "No GitHub remote was found for this repository."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if ConsolePullRequests.showsAuthHint(snapshot.pr.error) {
                VStack(alignment: .trailing, spacing: 3) {
                    Button(L10n.t("Copiar gh auth login", "Copy gh auth login")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("gh auth login", forType: .string)
                        ui.showAuthCommandCopied()
                    }
                    .controlSize(.small)
                    .help(L10n.t("Copia el comando para iniciar sesión en GitHub CLI",
                                 "Copies the command to sign in to the GitHub CLI"))
                    if ui.authCommandCopied {
                        Text(L10n.t("Copiado", "Copied"))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
        }
    }

    // MARK: - Per-project source freshness (S5)

    private var sourcesLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                sourceLine("Git", snapshot.git.freshness, snapshot.git.lastReadAt,
                           snapshot.git.error)
                sourceLine("GitHub", snapshot.pr.freshness, snapshot.pr.lastReadAt,
                           snapshot.pr.error)
                sourceLine("Engram", snapshot.activity.freshness,
                           snapshot.activity.lastReadAt, snapshot.activity.error)
                Spacer(minLength: 0)
            }
            // S5: a retained or missing value never hides the current failure.
            ForEach(sourceErrors, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    /// Current errors of every source that is not current, stale or unavailable.
    private var sourceErrors: [String] {
        [("Git", snapshot.git.freshness, snapshot.git.error),
         ("GitHub", snapshot.pr.freshness, snapshot.pr.error),
         ("Engram", snapshot.activity.freshness, snapshot.activity.error)]
            .compactMap { label, freshness, error in
                guard freshness != .current, let error else { return nil }
                return "\(label) · \(L10n.t("error actual", "current error")): \(error)"
            }
    }

    /// S5: each source keeps its own visible freshness in this project, with
    /// the current error available as a help tooltip.
    private func sourceLine(_ label: String, _ freshness: SourceFreshness,
                            _ lastReadAt: Date?, _ error: String?) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor(freshness))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("\(label) · \(sourceStateText(label, freshness))\(readTimeSuffix(lastReadAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(sourceHelp(label, freshness, lastReadAt, error))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sourceHelp(label, freshness, lastReadAt, error))
    }

    private func dotColor(_ freshness: SourceFreshness) -> Color {
        switch freshness {
        case .current: return .green
        case .stale: return .orange
        case .unavailable: return .secondary
        }
    }

    private func sourceStateText(_ label: String, _ freshness: SourceFreshness) -> String {
        switch freshness {
        case .current:
            return label == "Engram"
                ? L10n.t("conectado", "connected")
                : L10n.t("actual", "current")
        case .stale:
            return L10n.t("antiguo", "stale")
        case .unavailable:
            return label == "Engram"
                ? L10n.t("sin conexión", "not connected")
                : L10n.t("no disponible", "unavailable")
        }
    }

    private func readTimeSuffix(_ lastReadAt: Date?) -> String {
        guard let lastReadAt else { return "" }
        return " · \(lastReadAt.formatted(date: .omitted, time: .shortened))"
    }

    private func sourceHelp(_ label: String, _ freshness: SourceFreshness,
                            _ lastReadAt: Date?, _ error: String?) -> String {
        var parts = ["\(label): \(sourceStateText(label, freshness))"]
        if let lastReadAt {
            parts.append("\(L10n.t("última lectura", "last read")) "
                         + lastReadAt.formatted(date: .abbreviated, time: .standard))
        } else {
            parts.append(L10n.t("sin lecturas exitosas", "no successful reads"))
        }
        if let error {
            parts.append("\(L10n.t("error actual", "current error")): \(error)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Header actions

    /// S4: the primary action names the configured editor; without one it takes
    /// the owner to Settings instead of failing.
    private var editorName: String? {
        guard let path = appState.config.editorApplicationPath else { return nil }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private var editorActionTitle: String {
        guard let editorName else {
            return L10n.t("Configurar editor…", "Set up editor…")
        }
        return L10n.t("Abrir en \(editorName)", "Open in \(editorName)")
    }

    private var editorHelp: String {
        guard let path = appState.config.editorApplicationPath else {
            return L10n.t("Elige el editor de código en Ajustes",
                          "Choose the code editor in Settings")
        }
        return L10n.t("Abre el proyecto en \(path)",
                      "Opens the project in \(path)")
    }

    private func openEditor() {
        guard let editor = appState.config.editorApplicationPath else {
            onOpenSettings()
            return
        }
        launch(WorktreeActionCommand.openApplication(appPath: editor,
                                                     worktreePath: snapshot.config.path))
    }

    private func openTerminal() {
        launch(WorktreeActionCommand.openTerminal(worktreePath: snapshot.config.path))
    }

    /// Same non-blocking path the worktree actions use: the command runs off the
    /// main actor and only a failure description comes back.
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
            if let error { ui.actionError = error }
        }
    }

    private func openEngramTUI() {
        Task { @MainActor in
            if let error = await EngramTUI.open() { ui.actionError = error }
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: snapshot.config.path, isDirectory: true)
        ])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.config.path, forType: .string)
    }

    // MARK: - Helpers

    private var branchLabel: String {
        if let branch = snapshot.git.branch { return branch }
        return snapshot.git.freshness == .unavailable
            ? L10n.t("no disponible", "unavailable")
            : "detached"
    }

    private var abbreviatedPath: String {
        (snapshot.config.path as NSString).abbreviatingWithTildeInPath
    }

    /// S5: long relative age of the last commit ("4 days ago").
    private func longAge(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.lang == .spanish
            ? Locale(identifier: "es")
            : Locale(identifier: "en")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
