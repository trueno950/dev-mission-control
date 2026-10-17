import Foundation

/// One tracked local repository.
public struct RepoConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Absolute path to the repository working tree.
    public var path: String
    /// Optional override of the GitHub slug ("owner/name"). When nil, the
    /// slug is resolved from the repository's `origin` remote at scan time.
    public var githubSlug: String?
    /// Optional Engram project name. When nil, the repository folder name is used.
    public var engramProject: String?
    public var enabled: Bool

    public init(id: String, path: String, githubSlug: String? = nil,
                engramProject: String? = nil, enabled: Bool = true) {
        self.id = id
        self.path = path
        self.githubSlug = githubSlug
        self.engramProject = engramProject
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, githubSlug, engramProject, enabled
    }

    /// Tolerant decoding: new optional keys and omitted booleans fall back to
    /// defaults instead of failing the whole config file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        githubSlug = try container.decodeIfPresent(String.self, forKey: .githubSlug)
        engramProject = try container.decodeIfPresent(String.self, forKey: .engramProject)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Folder name of the repository path.
    public var folderName: String {
        (path as NSString).lastPathComponent
    }

    /// Engram project name used for activity lookups.
    public var resolvedEngramProject: String {
        engramProject ?? folderName
    }
}

/// Root configuration persisted as JSON in Application Support.
public struct AppConfig: Codable, Hashable, Sendable {
    public var repos: [RepoConfig]
    public var refreshIntervalMinutes: Int
    /// Worktrees idle for more than this many days are flagged.
    public var staleWorktreeDays: Int
    /// Open PRs older than this many days are flagged.
    public var stalePRDays: Int
    /// Projects without Engram activity for this many days are flagged.
    public var inactivityDays: Int

    public static let `default` = AppConfig()

    private enum CodingKeys: String, CodingKey {
        case repos, refreshIntervalMinutes, staleWorktreeDays, stalePRDays, inactivityDays
    }

    /// Tolerant decoding: omitted numeric settings fall back to defaults so a
    /// config written by an older version keeps loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        let config = AppConfig()
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self,
            forKey: .refreshIntervalMinutes) ?? config.refreshIntervalMinutes
        staleWorktreeDays = try container.decodeIfPresent(Int.self,
            forKey: .staleWorktreeDays) ?? config.staleWorktreeDays
        stalePRDays = try container.decodeIfPresent(Int.self,
            forKey: .stalePRDays) ?? config.stalePRDays
        inactivityDays = try container.decodeIfPresent(Int.self,
            forKey: .inactivityDays) ?? config.inactivityDays
    }

    public init(repos: [RepoConfig] = [],
                refreshIntervalMinutes: Int = 5,
                staleWorktreeDays: Int = 7,
                stalePRDays: Int = 7,
                inactivityDays: Int = 14) {
        self.repos = repos
        self.refreshIntervalMinutes = max(1, refreshIntervalMinutes)
        self.staleWorktreeDays = max(1, staleWorktreeDays)
        self.stalePRDays = max(1, stalePRDays)
        self.inactivityDays = max(1, inactivityDays)
    }
}

// MARK: - Scan results

/// Normalized working-tree change counts for one checkout or linked worktree,
/// derived from `git status --porcelain=v1`. The category counts describe
/// membership, so a file staged and then modified again appears in both
/// `staged` and `unstaged`; `pendingFiles` counts each porcelain entry once.
/// Unmerged (conflicted) entries are conflict evidence and are not also
/// counted as staged or unstaged.
public struct ChangeCounts: Hashable, Sendable {
    /// Entries with index (staged) changes: column `X` of porcelain v1.
    public var staged: Int
    /// Entries with working-tree (unstaged) changes: column `Y` of porcelain v1.
    public var unstaged: Int
    /// Untracked files (`??`).
    public var untracked: Int
    /// Unmerged entries (`DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`).
    public var conflicts: Int
    /// Distinct pending entries, one per file in `git status --porcelain=v1`.
    /// A file whose changes are both staged and unstaged counts once here while
    /// appearing in both `staged` and `unstaged`.
    public var pendingFiles: Int

    public static let none = ChangeCounts()

    public init(staged: Int = 0, unstaged: Int = 0, untracked: Int = 0, conflicts: Int = 0,
                pendingFiles: Int? = nil) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicts = conflicts
        // Callers that do not supply a line count are assumed to describe
        // disjoint categories; the parser always supplies the exact count.
        self.pendingFiles = pendingFiles ?? (staged + unstaged + untracked + conflicts)
    }

    /// Whether the checkout or worktree has any pending change.
    public var isDirty: Bool { pendingFiles > 0 }

    /// Whether the checkout or worktree holds an unmerged conflict.
    public var hasConflicts: Bool { conflicts > 0 }
}

/// A linked git worktree of a repository.
public struct WorktreeInfo: Hashable, Sendable {
    public var path: String
    public var name: String
    public var branch: String?
    /// Normalized staged/unstaged/untracked/conflict counts for this worktree.
    public var changes: ChangeCounts
    /// Whole days since the last commit, used for the idle threshold.
    public var ageDays: Int
    /// Nil when git could not read the worktree's last commit timestamp.
    public var lastCommitAt: Date?

    /// Backward-compatible: true when the worktree has any pending change.
    public var isDirty: Bool { changes.isDirty }
    /// Backward-compatible: number of pending files, equal to `changes.pendingFiles`.
    public var dirtyCount: Int { changes.pendingFiles }

    public init(path: String, name: String, isDirty: Bool, ageDays: Int,
                branch: String? = nil, dirtyCount: Int? = nil,
                lastCommitAt: Date? = nil, changes: ChangeCounts? = nil) {
        self.path = path
        self.name = name
        self.branch = branch
        // Legacy callers supply only `isDirty`/`dirtyCount`; they have no
        // category breakdown, so the total is attributed to unstaged changes.
        self.changes = changes ?? ChangeCounts(unstaged: dirtyCount ?? (isDirty ? 1 : 0))
        self.ageDays = ageDays
        self.lastCommitAt = lastCommitAt
    }
}

/// One open pull request with its CI state.
public struct PRInfo: Hashable, Sendable {
    public var number: Int
    public var title: String
    public var ageDays: Int
    public var ciFailing: Bool

    public init(number: Int, title: String, ageDays: Int, ciFailing: Bool) {
        self.number = number
        self.title = title
        self.ageDays = ageDays
        self.ciFailing = ciFailing
    }
}

/// Last recorded Engram activity for a project.
public struct ActivityInfo: Hashable, Sendable {
    public var title: String
    public var date: Date

    public init(title: String, date: Date) {
        self.title = title
        self.date = date
    }
}

/// Result of scanning one repository with local git.
public struct GitStatus: Hashable, Sendable {
    public var branch: String?
    /// Normalized staged/unstaged/untracked/conflict counts for the primary checkout.
    public var changes: ChangeCounts
    public var unpushedCount: Int
    public var worktrees: [WorktreeInfo]
    /// Non-nil when the repository could not be scanned (missing path, not a repo).
    public var error: String?

    /// Backward-compatible: number of pending files in the primary checkout.
    public var dirtyCount: Int { changes.pendingFiles }

    public init(branch: String? = nil, dirtyCount: Int = 0, unpushedCount: Int = 0,
                worktrees: [WorktreeInfo] = [], error: String? = nil,
                changes: ChangeCounts? = nil) {
        self.branch = branch
        // Legacy callers supply only `dirtyCount`; without a category
        // breakdown the total is attributed to unstaged changes.
        self.changes = changes ?? ChangeCounts(unstaged: dirtyCount)
        self.unpushedCount = unpushedCount
        self.worktrees = worktrees
        self.error = error
    }
}

/// Result of scanning one repository with the `gh` CLI.
public struct PRStatus: Hashable, Sendable {
    public var prs: [PRInfo]
    /// False when `gh` is missing, unauthenticated, or the call failed.
    public var available: Bool
    public var error: String?

    public init(prs: [PRInfo] = [], available: Bool = false, error: String? = nil) {
        self.prs = prs
        self.available = available
        self.error = error
    }
}

/// Result of the Engram activity lookup for one project.
public struct ActivityStatus: Hashable, Sendable {
    public var activity: ActivityInfo?
    /// False when the Engram server is unreachable or the request failed.
    public var available: Bool
    public var error: String?

    public init(activity: ActivityInfo? = nil, available: Bool = false, error: String? = nil) {
        self.activity = activity
        self.available = available
        self.error = error
    }
}

/// Everything known about one configured repository after one scan pass.
public struct RepoSnapshot: Hashable, Sendable {
    public var config: RepoConfig
    public var git: GitStatus
    public var pr: PRStatus
    public var activity: ActivityStatus

    public init(config: RepoConfig, git: GitStatus = GitStatus(),
                pr: PRStatus = PRStatus(), activity: ActivityStatus = ActivityStatus()) {
        self.config = config
        self.git = git
        self.pr = pr
        self.activity = activity
    }
}
