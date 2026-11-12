import SwiftUI
import DevControlCore

/// Visible title of one sidebar group (S3).
extension ProjectGroup {
    /// Group header copy, in triage order.
    var sidebarTitle: String {
        switch self {
        case .needsAction: return L10n.t("Necesitan acción", "Needs action")
        case .inProgress: return L10n.t("En curso", "In progress")
        case .toReview: return L10n.t("Para revisar", "To review")
        case .noData: return L10n.t("Sin datos", "No data")
        case .clean: return L10n.t("Limpios", "Clean")
        }
    }
}

/// Left column of the split console (S2/S3): the title, a refresh action, the
/// project filter and the grouped project list. Selection lives in the panel's
/// `PanelUIState`; the sidebar only reports the clicked row.
struct ConsoleSidebar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var ui: PanelUIState
    let sections: [ConsoleProjectSection]
    let selectedPath: String?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            header
            filterField
            Divider().opacity(0.25)
            list
        }
        .background(Color.black.opacity(0.12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Proyectos", "Projects"))
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.gradient)
                .accessibilityHidden(true)
            Text("Mission Control")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// S2: refresh now; the spinner replaces the button while a scan runs.
    @ViewBuilder private var refreshButton: some View {
        if appState.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(L10n.t("Escaneando", "Scanning"))
        } else {
            Button {
                appState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L10n.t("Escanear todos los proyectos", "Scan all projects"))
            .accessibilityLabel(L10n.t("Escanear todos los proyectos", "Scan all projects"))
        }
    }

    /// S2/S3: case-insensitive substring filter over the repository ids.
    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L10n.t("Filtrar proyectos", "Filter projects"), text: $ui.filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel(L10n.t("Filtrar proyectos", "Filter projects"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(sections) { section in
                    Text("\(section.group.sidebarTitle.uppercased()) · \(section.rows.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.rows) { row in
                        ConsoleProjectRowView(row: row,
                                              isSelected: row.id == selectedPath,
                                              now: now) {
                            ui.selectedPath = row.id
                        }
                    }
                }
                if sections.isEmpty {
                    Text(L10n.t("Sin proyectos para este filtro",
                                "No projects match this filter"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One project row (S3): a severity shape that is distinct by symbol and color,
/// the name, a short age and one reason line. The whole row is a focusable
/// button whose accessibility label names its group.
struct ConsoleProjectRowView: View {
    let row: ConsoleProjectRow
    let isSelected: Bool
    let now: Date
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 14, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        if let ageText {
                            Text(ageText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    if let reason {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Row content

    /// S3: the shape differs per state, so the group is never color alone.
    private var iconName: String {
        if row.snapshot.config.isPaused { return "pause.circle" }
        switch row.group {
        case .needsAction:
            return worstSeverity == .warning
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.octagon.fill"
        case .inProgress: return "pencil.circle"
        case .toReview: return "circle"
        case .noData: return "questionmark.circle"
        case .clean: return "checkmark.circle"
        }
    }

    private var iconColor: Color {
        if row.snapshot.config.isPaused { return .secondary }
        switch row.group {
        case .needsAction: return worstSeverity == .warning ? .orange : .red
        case .inProgress: return .accentColor
        case .toReview, .noData: return .secondary
        case .clean: return .green
        }
    }

    /// Needs-action rows always carry a warning or critical finding; the
    /// fallback only keeps the shape deterministic.
    private var worstSeverity: AttentionItem.Severity { row.severity ?? .critical }

    /// S3: paused projects say so where the age would be.
    private var ageText: String? {
        if row.snapshot.config.isPaused { return L10n.t("Pausado", "Paused") }
        guard let lastTouched = row.lastTouched else { return nil }
        return RelativeAge.short(from: lastTouched, to: now, language: L10n.lang)
    }

    /// S3: one line saying why the project is in its group.
    private var reason: String? {
        switch row.group {
        case .needsAction, .toReview:
            return row.items.first?.message
        case .inProgress:
            let pending = ConsoleWorktreeSummary.pendingChangeCount(row.snapshot)
            guard pending > 0 else { return nil }
            return L10n.t("\(pending) cambios pendientes", "\(pending) pending changes")
        case .noData:
            return row.snapshot.git.error ?? L10n.t("Git no disponible", "Git unavailable")
        case .clean:
            return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = [L10n.t("Proyecto \(row.name)", "Project \(row.name)"),
                     row.group.sidebarTitle]
        if let ageText { parts.append(ageText) }
        if let reason { parts.append(reason) }
        return parts.joined(separator: ", ")
    }
}
