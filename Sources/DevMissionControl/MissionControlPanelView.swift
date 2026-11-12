import AppKit
import SwiftUI
import DevControlCore

/// Local UI state of the split console: the selected repository path and the
/// project filter. Held in an ObservableObject because this environment cannot
/// load the `@State` macro.
@MainActor
final class PanelUIState: ObservableObject {
    @Published var selectedPath: String?
    @Published var filter = ""
}

/// Root view of the panel (S2): a 760 × 600 split console with the project list
/// on the left, the selected project's detail on the right, and one footer
/// spanning both columns. Replaces the compact cards and the separate
/// repository detail window. All copy follows the system language.
struct MissionControlPanelView: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void
    let onOpenEngramPanel: (String) -> Void
    let onCopyRetakeContext: (String) async -> String?
    @StateObject private var ui = PanelUIState()

    private var now: Date { Date() }

    /// S3: grouped, filtered and ordered rows of the sidebar.
    private var sections: [ConsoleProjectSection] {
        ConsoleProjectList.sections(appState.consoleRows, filter: ui.filter)
    }

    /// S3: the live selection. A nil selection and a selection whose repository
    /// vanished both fall back to the first row in triage order.
    private var selectedPath: String? {
        ConsoleProjectList.selection(in: sections, current: ui.selectedPath)
    }

    private var selectedSnapshot: RepoSnapshot? {
        guard let selectedPath,
              let snapshot = appState.snapshots.first(where: { $0.config.path == selectedPath })
        else { return nil }
        return appState.liveSnapshot(for: snapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ConsoleSidebar(appState: appState,
                               ui: ui,
                               sections: sections,
                               selectedPath: selectedPath,
                               now: now)
                    .frame(width: 250)
                Divider().opacity(0.25)
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.25)
            ConsoleFooter(appState: appState, onOpenSettings: onOpenSettings)
        }
        .frame(width: 760, height: 600)
        .background(VisualEffectBackground().ignoresSafeArea())
        .onAppear {
            if ui.selectedPath == nil { ui.selectedPath = selectedPath }
        }
    }

    // MARK: - Detail pane

    @ViewBuilder private var detail: some View {
        if appState.config.repos.isEmpty {
            noProjectsState
        } else if let snapshot = selectedSnapshot {
            ConsoleDetailView(appState: appState,
                              snapshot: snapshot,
                              now: now,
                              onOpenSettings: onOpenSettings,
                              onOpenEngramPanel: onOpenEngramPanel,
                              onCopyRetakeContext: onCopyRetakeContext)
                // A different project starts with its own detail state.
                .id(snapshot.config.path)
        } else if appState.snapshots.isEmpty {
            scanningState
        } else {
            noMatchesState
        }
    }

    /// A filter that matches nothing is said plainly, never shown as a scan.
    private var noMatchesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L10n.t("Ningún proyecto coincide con «\(ui.filter)»",
                        "No projects match “\(ui.filter)”"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(L10n.t("Limpiar filtro", "Clear filter")) { ui.filter = "" }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var noProjectsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L10n.t("No hay proyectos seguidos", "No projects tracked yet"))
                .font(.headline)
            Text(L10n.t("Agrega repositorios…", "Add repositories…"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L10n.t("Abrir ajustes", "Open Settings"), action: onOpenSettings)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.t("Escaneando…", "Scanning…"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

/// Footer spanning both columns (S2): one aggregate per source, the next scan,
/// and Settings. The periodic timeline keeps the relative times current without
/// a scan; Quit stays in the status item's right-click menu.
struct ConsoleFooter: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 14) {
                source(ConsoleSource.git, now: context.date)
                source(ConsoleSource.github, now: context.date)
                source(ConsoleSource.engram, now: context.date)
                Spacer(minLength: 8)
                Text(nextScanLabel(now: context.date))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help(L10n.t("Ajustes (⌘,)", "Settings (⌘,)"))
                .accessibilityLabel(L10n.t("Ajustes", "Settings"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func source(_ source: ConsoleSource, now: Date) -> some View {
        let rollup = ConsoleSourceRollup.make(appState.snapshots, source: source)
        return HStack(spacing: 5) {
            dot(rollup.dot)
            Text(rollup.text(lastRefresh: appState.lastRefresh, now: now,
                             language: L10n.lang))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(L10n.t("\(source.label): \(rollup.currentCount) de \(rollup.total) proyectos leídos",
                     "\(source.label): \(rollup.currentCount) of \(rollup.total) projects read"))
        .accessibilityElement(children: .combine)
    }

    /// Green when every project's read is current, orange when some read is not,
    /// hollow when there is no current read at all (S2).
    @ViewBuilder private func dot(_ dot: ConsoleSourceRollup.Dot) -> some View {
        switch dot {
        case .current:
            Circle().fill(Color.green).frame(width: 7, height: 7)
        case .stale:
            Circle().fill(Color.orange).frame(width: 7, height: 7)
        case .none:
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }

    private func nextScanLabel(now: Date) -> String {
        if appState.isRefreshing {
            return L10n.t("Escaneando…", "Scanning…")
        }
        let interval = TimeInterval(appState.config.refreshIntervalMinutes * 60)
        guard let lastRefresh = appState.lastRefresh else {
            let minutes = appState.config.refreshIntervalMinutes
            return L10n.t("Próximo escaneo en \(minutes) min",
                          "Next scan in \(minutes) min")
        }
        let remaining = max(0, lastRefresh.addingTimeInterval(interval).timeIntervalSince(now))
        let minutes = Int((remaining / 60).rounded(.up))
        return L10n.t("Próximo escaneo en \(minutes) min", "Next scan in \(minutes) min")
    }
}
