import Foundation
import Combine
import DevControlCore

/// Single source of truth shared by the panel and the settings window.
/// Owns the configuration and the scan pipeline; mutations persist
/// immediately. Scans run off the main actor and publish snapshots back.
@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            if oldValue != config { persist() }
            rescheduleAutoRefresh()
        }
    }
    @Published private(set) var snapshots: [RepoSnapshot] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private let store: ConfigStore
    private let gitScanner: GitScanner
    private let ghScanner: GhScanner
    private let engramScanner: EngramScanner
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    nonisolated static func makeDefaultStore() -> ConfigStore {
        if let store = try? ConfigStore(directory: ConfigStore.appSupportDirectory()) {
            return store
        }
        return try! ConfigStore(directory: FileManager.default.temporaryDirectory)
    }

    init(store: ConfigStore = AppState.makeDefaultStore(),
         gitScanner: GitScanner = GitScanner(),
         ghScanner: GhScanner = GhScanner(),
         engramScanner: EngramScanner = EngramScanner()) {
        self.store = store
        self.gitScanner = gitScanner
        self.ghScanner = ghScanner
        self.engramScanner = engramScanner
        self.config = (try? store.load()) ?? .default
    }

    private func persist() {
        try? store.save(config)
    }

    // MARK: - Derived values

    func items(for snapshot: RepoSnapshot) -> [AttentionItem] {
        AttentionMath.classify(snapshot, now: Date(), calendar: .current,
                               thresholds: config)
    }

    /// Repositories currently needing attention, ordered by severity of their
    /// worst item (critical first), then by name.
    var attentionOrder: [RepoSnapshot] {
        snapshots.filter { !items(for: $0).isEmpty }
            .sorted { lhs, rhs in
                let lhsWorst = items(for: lhs).first?.severity ?? .info
                let rhsWorst = items(for: rhs).first?.severity ?? .info
                if lhsWorst != rhsWorst { return lhsWorst > rhsWorst }
                return lhs.config.id < rhs.config.id
            }
    }

    var cleanOrder: [RepoSnapshot] {
        snapshots.filter { items(for: $0).isEmpty }
            .sorted { $0.config.id < $1.config.id }
    }

    var attentionCount: Int { attentionOrder.count }

    // MARK: - Refresh pipeline

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let repos = config.repos.filter { $0.enabled }
        let gitScanner = gitScanner
        let ghScanner = ghScanner
        let engramScanner = engramScanner
        let now = Date()

        refreshTask = Task { [weak self] in
            var snapshots = await withTaskGroup(of: RepoSnapshot.self) { group in
                for repo in repos {
                    group.addTask {
                        let git = gitScanner.scan(repoPath: repo.path, now: now)
                        let pr = ghScanner.scan(repoPath: repo.path,
                                                slugOverride: repo.githubSlug, now: now)
                        let activity = await engramScanner.scan(
                            project: repo.resolvedEngramProject)
                        return RepoSnapshot(config: repo, git: git, pr: pr,
                                            activity: activity)
                    }
                }
                var collected: [RepoSnapshot] = []
                for await snapshot in group { collected.append(snapshot) }
                return collected
            }
            snapshots.sort { $0.config.id < $1.config.id }

            await MainActor.run { [weak self] in
                self?.snapshots = snapshots
                self?.lastRefresh = Date()
                self?.isRefreshing = false
            }
        }
    }

    // MARK: - Auto refresh

    func startAutoRefresh() {
        rescheduleAutoRefresh()
        if lastRefresh == nil { refresh() }
    }

    private func rescheduleAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(config.refreshIntervalMinutes * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Config mutations (settings window)

    func addRepo(path: String) {
        let standardized = (path as NSString).standardizingPath
        guard !standardized.isEmpty,
              !config.repos.contains(where: { $0.path == standardized }) else { return }
        let name = (standardized as NSString).lastPathComponent
        config.repos.append(RepoConfig(id: name, path: standardized))
    }

    func removeRepo(id: String) {
        config.repos.removeAll { $0.id == id }
    }
}
