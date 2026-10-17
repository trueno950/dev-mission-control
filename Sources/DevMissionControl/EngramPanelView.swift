import AppKit
import SwiftUI
import DevControlCore

// Read-only Engram panel (S2/S5/S6). One activating window per repository
// shows real counters from `GET /stats`, the latest memories with their full
// content, and one freshness line per source. Every user-visible string goes
// through `L10n.t(es, en)`. Nothing here writes to Engram, opens its SQLite,
// or calls a model.

/// Shared launcher for the supported Engram terminal UI (S7). The command is
/// fixed (no user paths) and runs through `osascript` with separate arguments.
/// Used by both the panel and the source freshness badge so there is a single
/// implementation. The TUI is global and slow, which the callers label
/// honestly; this helper only surfaces a failure description.
enum EngramTUI {
    static func open() async -> String? {
        let script = "tell application \"Terminal\" to do script \"engram tui\""
        return await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                _ = try ProcessRunner().run("/usr/bin/osascript", ["-e", script], in: nil)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
    }
}

/// Opens one activating Engram panel window per repository (S2). State is kept
/// per repository path so a reused window keeps its reads and selection.
@MainActor
final class EngramPanelWindowController {
    private var windows: [String: NSWindow] = [:]
    private var states: [String: EngramPanelState] = [:]

    func show(appState: AppState, repoPath: String) {
        let state: EngramPanelState
        if let existing = states[repoPath] {
            state = existing
        } else {
            let snapshot = appState.snapshots.first { $0.config.path == repoPath }
            let name = snapshot?.config.id ?? (repoPath as NSString).lastPathComponent
            state = EngramPanelState(repoPath: repoPath,
                                     repoName: name,
                                     configuredEngramProject: snapshot?.config.engramProject)
            states[repoPath] = state
        }

        let window: NSWindow
        if let existing = windows[repoPath] {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: EngramPanelView(state: state))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 640, height: 720))
            newWindow.isReleasedWhenClosed = false
            newWindow.title = L10n.t("Mission Control — Memorias · \(state.repoName)",
                                     "Mission Control — Memories · \(state.repoName)")
            windows[repoPath] = newWindow
            window = newWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Where the Engram project name for a repository came from (S4). Shown
/// explicitly so the match is never implied.
enum EngramProjectOrigin {
    case directory
    case configured
    case folderName

    var label: String {
        switch self {
        case .directory: return L10n.t("coincide por directorio", "matched by directory")
        case .configured: return L10n.t("nombre configurado", "configured name")
        case .folderName: return L10n.t("por nombre de carpeta", "by folder name")
        }
    }
}

/// Read state for one repository's Engram panel. Owned by the window
/// controller and shared with the view so a reused window keeps its data.
/// Held in an ObservableObject because this environment cannot load the
/// `@State` macro. Each source keeps its own `EngramRead`, so a failed read
/// retains the last good value marked stale while the current error stays
/// visible and an empty list is never rendered as a success (S5).
@MainActor
final class EngramPanelState: ObservableObject {
    @Published private(set) var projectName: String?
    @Published private(set) var projectOrigin: EngramProjectOrigin = .folderName
    @Published private(set) var projectsRead: EngramRead<[EngramProjectEntry]>?
    @Published private(set) var statsRead: EngramRead<EngramProjectStats>?
    @Published private(set) var memoriesRead: EngramRead<[EngramMemory]>?
    @Published private(set) var isLoading = false
    /// In-app search over `GET /search` (S2). The query is user input and the
    /// read is kept apart from `memoriesRead`, so a search never overwrites the
    /// latest-memories source and each one keeps its own freshness (S5).
    @Published var searchQuery = ""
    @Published private(set) var searchRead: EngramRead<[EngramMemory]>?
    /// True only while a search request is in flight.
    @Published private(set) var isSearching = false
    /// Selected memory's id; selecting expands its full content. Kept on the
    /// state so later search and sessions views can reuse the same selection.
    @Published var selectedMemoryID: Int?
    @Published var tuiError: String?

    /// Both memory lists read the same number of rows.
    private static let memoriesLimit = 20
    /// Idle wait before a search is issued while the user types.
    private static let searchDebounce: Duration = .milliseconds(350)

    let repoPath: String
    let repoName: String
    let configuredEngramProject: String?
    private let client: EngramPanelClient
    /// Query the most recent search request was issued for. A reply whose query
    /// is no longer current is discarded, so out-of-order responses cannot
    /// overwrite a newer search.
    private var issuedSearchQuery: String?
    /// Pending idle-debounce task; cancelled by the next keystroke or submit.
    private var searchDebounceTask: Task<Void, Never>?

    init(repoPath: String, repoName: String, configuredEngramProject: String?,
         client: EngramPanelClient = EngramPanelClient()) {
        self.repoPath = repoPath
        self.repoName = repoName
        self.configuredEngramProject = configuredEngramProject
        self.client = client
    }

    /// One read pass over every panel source (S3/S4/S5). The project is
    /// resolved once from `/projects`, then `stats` and `memories` (limit 20)
    /// are read for it. A failed read is applied through `retainingLastRead`,
    /// so the previous good value is kept marked stale.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let client = self.client
        let projects = await client.projects()
        let resolution = EngramProjectResolver.resolve(
            repoPath: repoPath,
            entries: projects.value ?? [],
            configuredName: configuredEngramProject)
        projectName = resolution.project
        if let configured = configuredEngramProject,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectOrigin = .configured
        } else if resolution.matchedByDirectory {
            projectOrigin = .directory
        } else {
            projectOrigin = .folderName
        }
        projectsRead = projects.retainingLastRead(projectsRead)

        async let stats = client.stats(project: resolution.project)
        async let memories = client.memories(project: resolution.project,
                                            limit: Self.memoriesLimit)
        let (newStats, newMemories) = await (stats, memories)
        statsRead = newStats.retainingLastRead(statsRead)
        memoriesRead = newMemories.retainingLastRead(memoriesRead)
    }

    // MARK: - Search (S2)

    /// Search input without surrounding whitespace. A blank query counts as
    /// empty so the panel keeps showing the latest-memories list.
    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while a query is active. Only then are the search source and its
    /// results shown; an empty query leaves the panel exactly as it was.
    var isSearchActive: Bool { !normalizedSearchQuery.isEmpty }

    /// Project the search runs against (S4): the one `load()` resolved when it
    /// already ran, otherwise the same resolver applied to the last
    /// `/projects` read, so no project name is invented here.
    private var searchProject: String {
        if let projectName { return projectName }
        return EngramProjectResolver.resolve(
            repoPath: repoPath,
            entries: projectsRead?.value ?? [],
            configuredName: configuredEngramProject).project
    }

    /// One search for the current query (S2). A blank query clears the search
    /// source instead of issuing a request. The reply is applied only when the
    /// query it was issued for is still the current one, so a slow response can
    /// never overwrite a newer search.
    func runSearch() async {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        issuedSearchQuery = query
        isSearching = true
        let read = await client.search(query: query, project: searchProject,
                                       limit: Self.memoriesLimit)
        // Out-of-order guard: the query changed or was cleared while this
        // request was in flight, so its reply is discarded (and its spinner is
        // left to the request that is still current).
        guard issuedSearchQuery == query, normalizedSearchQuery == query else { return }
        isSearching = false
        searchRead = read.retainingLastRead(searchRead)
    }

    /// Idle debounce after a keystroke: only the last edit of a burst issues a
    /// request, so typing never produces one request per keystroke.
    func searchQueryDidChange() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        guard isSearchActive else {
            clearSearch()
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch()
        }
    }

    /// Enter: search now, cancelling any pending debounce.
    func submitSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        guard isSearchActive else {
            clearSearch()
            return
        }
        Task { await runSearch() }
    }

    /// Drops the search source and makes any pending or in-flight request
    /// non-current, so its reply is discarded instead of reviving old results.
    func clearSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        issuedSearchQuery = nil
        isSearching = false
        searchRead = nil
    }
}

/// Read-only Engram panel for one repository (S2). Shows the resolved project
/// and its match origin, per-source freshness, real counters, and the latest
/// memories with their full content and a copy action.
struct EngramPanelView: View {
    @ObservedObject var state: EngramPanelState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    freshnessSection
                    countersSection
                    searchField
                    memoriesSection
                }
                .padding(14)
            }
            Divider().opacity(0.25)
            footer
        }
        .frame(minWidth: 620, minHeight: 680)
        .task { await state.load() }
        .alert(L10n.t("No se pudo abrir el TUI de Engram", "Could not open the Engram TUI"),
               isPresented: Binding(
            get: { state.tuiError != nil },
            set: { if !$0 { state.tuiError = nil } }
        )) {
            Button("OK", role: .cancel) { state.tuiError = nil }
        } message: {
            Text(state.tuiError ?? L10n.t("Error desconocido", "Unknown error"))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.cyan.gradient)
                Text(state.repoName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                refreshButton
            }
            HStack(spacing: 6) {
                Text(L10n.t("Proyecto Engram ·", "Engram project ·"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.projectName ?? L10n.t("sin resolver", "unresolved"))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Text("· \(state.projectOrigin.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var refreshButton: some View {
        if state.isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(.leading, 4)
        } else {
            Button {
                Task { await state.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.leading, 4)
            .help(L10n.t("Volver a leer Engram", "Re-read Engram"))
        }
    }

    // MARK: - Freshness

    private var freshnessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Fuentes", "Sources"))
                .font(.caption.weight(.semibold))
            freshnessLine(L10n.t("Proyecto", "Project"), read: state.projectsRead)
            freshnessLine(L10n.t("Contadores", "Counters"), read: state.statsRead)
            freshnessLine(L10n.t("Memorias", "Memories"), read: state.memoriesRead)
            // The search is a source of its own, so it gets its own line with
            // its read time and current failure. It only exists once a query
            // was searched, so an empty query keeps this list as it was.
            if state.isSearchActive, state.searchRead != nil {
                freshnessLine(L10n.t("Búsqueda", "Search"), read: state.searchRead)
            }
        }
    }

    // MARK: - Search field

    /// In-app search over `/search` (S2). Typing only schedules the idle
    /// debounce; Enter searches immediately and the clear button returns the
    /// panel to the latest-memories list.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(L10n.t("Buscar en las memorias…", "Search memories…"),
                      text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit { state.submitSearch() }
            if state.isSearching {
                ProgressView()
                    .controlSize(.mini)
            } else if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                    state.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help(L10n.t("Borrar la búsqueda", "Clear the search"))
                .accessibilityLabel(L10n.t("Borrar la búsqueda", "Clear the search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(L10n.t("Busca en las memorias de Engram de este proyecto. Con Enter busca al momento; al dejar de escribir también busca.",
                     "Searches this project's Engram memories. Enter searches right away; pausing the typing searches too."))
        .onChange(of: state.searchQuery) { _ in state.searchQueryDidChange() }
    }

    /// One freshness line per source with its read time (S5). A stale value
    /// keeps its read time and still shows the current failure.
    private func freshnessLine<Value: Hashable & Sendable>(
        _ name: String, read: EngramRead<Value>?
    ) -> some View {
        let freshness = read?.freshness ?? .unavailable
        return HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(statusColor(freshness))
                .frame(width: 5, height: 5)
                .padding(.top, 3)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(stateText(freshness)) · \(readTimeText(read?.lastReadAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = read?.error {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Counters

    @ViewBuilder private var countersSection: some View {
        if let stats = state.statsRead?.value {
            HStack(spacing: 10) {
                statCard(L10n.t("Sesiones", "Sessions"), stats.sessions)
                statCard(L10n.t("Observaciones", "Observations"), stats.observations)
                statCard(L10n.t("Prompts", "Prompts"), stats.prompts)
            }
        } else if state.isLoading, state.statsRead == nil {
            Text(L10n.t("Cargando contadores…", "Loading counters…"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            noInformation(state.statsRead?.error)
        }
    }

    private func statCard(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Memories

    /// A non-empty query shows the search results; an empty one keeps the
    /// latest-memories list exactly as it was before the search existed.
    @ViewBuilder private var memoriesSection: some View {
        if state.isSearchActive {
            searchResultsSection
        } else {
            latestMemoriesSection
        }
    }

    @ViewBuilder private var latestMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.t("Últimas memorias", "Latest memories"))
                    .font(.caption.weight(.semibold))
                if state.memoriesRead?.freshness == .stale {
                    staleBadge
                }
                Spacer(minLength: 2)
            }
            if let memories = state.memoriesRead?.value {
                if memories.isEmpty {
                    // A successful read with no entries is a real empty result.
                    Text(L10n.t("Sin memorias para este proyecto.", "No memories for this project."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memories) { memory in
                        memoryRow(memory)
                    }
                }
            } else if state.isLoading, state.memoriesRead == nil {
                Text(L10n.t("Cargando memorias…", "Loading memories…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                noInformation(state.memoriesRead?.error)
            }
        }
    }

    /// Search results over `/search` (S2/S5), rendered with the same memory row
    /// as the latest-memories list. Its own read decides what is shown: a failed
    /// search keeps the last good hits marked stale, a successful search with no
    /// hits says so, and a read without a value is never an empty success.
    @ViewBuilder private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.t("Resultados de la búsqueda", "Search results"))
                    .font(.caption.weight(.semibold))
                if state.searchRead?.freshness == .stale {
                    staleBadge
                }
                Spacer(minLength: 2)
            }
            if let results = state.searchRead?.value {
                if results.isEmpty {
                    // A successful search with no hits is a real empty result,
                    // never rendered as "no information" (S5).
                    Text(L10n.t("Sin resultados para esta búsqueda.",
                                "No results for this search."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { memory in
                        memoryRow(memory)
                    }
                }
            } else if state.searchRead == nil {
                // No search read yet: a pending debounce or a request still in
                // flight. That is not the same as having no information.
                Text(L10n.t("Buscando memorias…", "Searching memories…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                noInformation(state.searchRead?.error)
            }
        }
    }

    private var staleBadge: some View {
        Text(L10n.t("· datos antiguos", "· stale data"))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func memoryRow(_ memory: EngramMemory) -> some View {
        let isSelected = state.selectedMemoryID == memory.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let type = memory.type {
                            Text(type)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                        Text(memory.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let date = memory.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                copyButton(memory)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                state.selectedMemoryID = isSelected ? nil : memory.id
            }

            if isSelected {
                ScrollView {
                    Text(memory.content)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 220)
                .background(.quaternary.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func copyButton(_ memory: EngramMemory) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(memory.content, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
        .help(L10n.t("Copiar el contenido de la memoria", "Copy the memory content"))
        .accessibilityLabel(L10n.t("Copiar la memoria \(memory.title)",
                                   "Copy memory \(memory.title)"))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Solo lectura · Engram", "Read-only · Engram"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openTUI()
            } label: {
                Label(L10n.t("TUI global (tarda unos segundos)", "Global TUI (takes a few seconds)"),
                      systemImage: "terminal")
            }
            .controlSize(.small)
            .help(L10n.t("Abre el TUI de Engram en Terminal. Es global (no por proyecto) y tarda unos ~5 s.",
                         "Opens the Engram TUI in Terminal. It is global (not per project) and takes ~5 s."))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func openTUI() {
        Task { @MainActor in
            if let error = await EngramTUI.open() {
                state.tuiError = error
            }
        }
    }

    /// Explicit no-value state: the read has no value, so it is never shown as
    /// an empty success. The current error stays visible when present (S5).
    private func noInformation(_ error: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("Sin información.", "No information available."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusColor(_ freshness: SourceFreshness) -> Color {
        switch freshness {
        case .current: return .green
        case .stale: return .orange
        case .unavailable: return .secondary
        }
    }

    private func stateText(_ freshness: SourceFreshness) -> String {
        switch freshness {
        case .current: return L10n.t("actual", "current")
        case .stale: return L10n.t("antiguo", "stale")
        case .unavailable: return L10n.t("sin conexión", "no connection")
        }
    }

    /// Localized read time: "hoy 14:32" / "Today 14:32" for today, otherwise a
    /// short date and time. A missing read time is stated as such.
    private func readTimeText(_ date: Date?) -> String {
        guard let date else { return L10n.t("sin lectura", "no read") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            let clock = formatter.string(from: date)
            return L10n.t("hoy \(clock)", "Today \(clock)")
        }
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
