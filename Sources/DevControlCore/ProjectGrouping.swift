import Foundation

/// Sidebar group of the split console panel (S3). Declaration order is the
/// triage order shown to the owner: the groups that need a decision first.
public enum ProjectGroup: Int, CaseIterable, Comparable, Sendable {
    case needsAction
    case inProgress
    case toReview
    case noData
    case clean

    public static func < (lhs: ProjectGroup, rhs: ProjectGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Pure classification of one repository snapshot into a sidebar group (S3).
public enum ProjectGrouping {
    /// Groups one snapshot from its current findings. Warnings and critical
    /// findings outrank everything else; an unavailable or stale Git read is
    /// "No data" rather than "Clean" (S5), and pending changes are
    /// informational so they get their own "In progress" group.
    public static func group(_ snapshot: RepoSnapshot, items: [AttentionItem]) -> ProjectGroup {
        if AttentionMath.needsAttention(items) { return .needsAction }
        if snapshot.git.freshness != .current { return .noData }
        let hasPendingChanges = snapshot.git.changes.isDirty
            || snapshot.git.worktrees.contains { $0.isDirty }
        if hasPendingChanges { return .inProgress }
        return items.isEmpty ? .clean : .toReview
    }

    /// S5: the newest evidence of work on the project, from its last commit or
    /// its latest Engram memory. Nil when neither source has a date.
    public static func lastTouched(_ snapshot: RepoSnapshot) -> Date? {
        let dates = [snapshot.git.lastCommit?.date, snapshot.activity.activity?.date]
            .compactMap { $0 }
        return dates.max()
    }
}

/// Short relative age for a sidebar row (S3): "40m", "3h", "4d", "3w".
public enum RelativeAge {
    /// Formats the age of `date` at `now` using floor division. A future date
    /// (clock skew) and anything under a minute read as "now".
    public static func short(from date: Date, to now: Date, language: AppLanguage) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return language.pick(es: "ahora", en: "now") }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 14 { return "\(days)d" }
        return "\(days / 7)w"
    }
}

// MARK: - Split console sidebar (S2/S3)

/// One project row of the split console sidebar (S3): its snapshot, the group
/// it belongs to, the findings behind it, and the age basis used both for the
/// row's short age and for ordering inside non-action groups.
public struct ConsoleProjectRow: Hashable, Sendable, Identifiable {
    public var snapshot: RepoSnapshot
    public var items: [AttentionItem]
    public var group: ProjectGroup
    public var lastTouched: Date?

    public init(snapshot: RepoSnapshot, items: [AttentionItem]) {
        self.snapshot = snapshot
        self.items = items
        self.group = ProjectGrouping.group(snapshot, items: items)
        self.lastTouched = ProjectGrouping.lastTouched(snapshot)
    }

    /// Row identity is the repository path, which is stable across rescans.
    public var id: String { snapshot.config.path }
    public var name: String { snapshot.config.id }
    /// Worst finding severity, or nil when the project has no finding.
    public var severity: AttentionItem.Severity? { items.first?.severity }
}

/// A non-empty sidebar group and its ordered rows (S3).
public struct ConsoleProjectSection: Hashable, Sendable, Identifiable {
    public var group: ProjectGroup
    public var rows: [ConsoleProjectRow]

    /// Section identity is the group itself; a group appears at most once.
    public var id: Int { group.rawValue }
}

/// Sidebar composition of the split console (S3): group order, filtering,
/// ordering inside a group, and the selection fallback.
public enum ConsoleProjectList {
    /// Groups the rows in triage order, dropping empty groups, after applying
    /// the case-insensitive substring filter on the repository id. Inside
    /// "Needs action" the worst severity comes first (then name); every other
    /// group lists the most recently touched project first, unknown age last,
    /// with the name as the tiebreak.
    public static func sections(_ rows: [ConsoleProjectRow],
                                filter: String) -> [ConsoleProjectSection] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = needle.isEmpty
            ? rows
            : rows.filter { $0.name.lowercased().contains(needle) }
        return ProjectGroup.allCases.compactMap { group in
            let grouped = matching.filter { $0.group == group }.sorted(by: isOrderedBefore)
            return grouped.isEmpty ? nil : ConsoleProjectSection(group: group, rows: grouped)
        }
    }

    /// Selected path: the current selection while its row still exists,
    /// otherwise the first row in triage order (nil when nothing is listed).
    public static func selection(in sections: [ConsoleProjectSection],
                                 current: String?) -> String? {
        if let current, sections.contains(where: { section in
            section.rows.contains { $0.id == current }
        }) {
            return current
        }
        return sections.first?.rows.first?.id
    }

    /// S3 ordering inside one group. `sorted(by:)` needs a strict weak order,
    /// so equal rows fall through to the path for a deterministic result.
    private static func isOrderedBefore(_ lhs: ConsoleProjectRow,
                                        _ rhs: ConsoleProjectRow) -> Bool {
        if lhs.group == .needsAction {
            let left = lhs.severity ?? .info
            let right = rhs.severity ?? .info
            if left != right { return left > right }
        } else {
            switch (lhs.lastTouched, rhs.lastTouched) {
            case let (left?, right?):
                if left != right { return left > right }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }
        }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

// MARK: - Worktrees section (S6)

/// State pill of one worktree row (S6). `kind` drives the pill color; the text
/// never shows a zero counter.
public struct ConsoleWorktreeState: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case conflicts
        case pending
        case clean
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Worktree summaries of the split console detail pane (S6).
public enum ConsoleWorktreeSummary {
    /// State pill for one worktree: conflicts, then pending changes, else
    /// clean. A clean worktree never renders as "0 changes".
    public static func state(_ worktree: WorktreeInfo,
                             language: AppLanguage) -> ConsoleWorktreeState {
        let changes = worktree.changes
        if changes.conflicts > 0 {
            return ConsoleWorktreeState(kind: .conflicts, text: language.pick(
                es: "\(changes.conflicts) \(AppLanguage.plural(changes.conflicts, "conflicto", "conflictos"))",
                en: "\(changes.conflicts) \(AppLanguage.plural(changes.conflicts, "conflict", "conflicts"))"))
        }
        if changes.pendingFiles > 0 {
            return ConsoleWorktreeState(kind: .pending, text: language.pick(
                es: "\(changes.pendingFiles) \(AppLanguage.plural(changes.pendingFiles, "cambio", "cambios"))",
                en: "\(changes.pendingFiles) changed"))
        }
        return ConsoleWorktreeState(kind: .clean,
                                    text: language.pick(es: "Limpio", en: "Clean"))
    }

    /// Prior S7/S10: staged, unstaged and untracked counts stay separate under
    /// the state pill. Zero categories are omitted, and conflicts are left to
    /// the pill. The labels are technical terms and stay in English.
    public static func breakdown(_ changes: ChangeCounts) -> [String] {
        [("Staged", changes.staged), ("Unstaged", changes.unstaged), ("Untracked", changes.untracked)]
            .filter { $0.1 > 0 }
            .map { "\($0.0) \($0.1)" }
    }

    /// Pending files across the primary checkout and every linked worktree,
    /// the sidebar's "N pending changes" reason (S3).
    public static func pendingChangeCount(_ snapshot: RepoSnapshot) -> Int {
        snapshot.git.changes.pendingFiles
            + snapshot.git.worktrees.reduce(0) { $0 + $1.changes.pendingFiles }
    }

    /// Headline of the single grouped block for clean idle worktrees (S6):
    /// "4 clean worktrees, idle 15–17 days", a single value when the range has
    /// one value, and an explicit "no dates" when none has a commit date.
    public static func cleanHeadline(_ worktrees: [WorktreeInfo],
                                     language: AppLanguage) -> String {
        let count = worktrees.count
        let noun = language.pick(
            es: "\(count) worktree\(count == 1 ? "" : "s") limpio\(count == 1 ? "" : "s")",
            en: "\(count) clean worktree\(count == 1 ? "" : "s")")
        let idle = language.pick(es: count == 1 ? "inactivo" : "inactivos", en: "idle")
        let ages = worktrees.compactMap { $0.lastCommitAt == nil ? nil : $0.ageDays }
        let value: String
        if let oldest = ages.max(), let newest = ages.min() {
            let range = newest == oldest ? "\(oldest)" : "\(newest)–\(oldest)"
            value = language.pick(
                es: "\(range) \(AppLanguage.plural(oldest, "día", "días"))",
                en: "\(range) \(AppLanguage.plural(oldest, "day", "days"))")
        } else {
            value = language.pick(es: "sin fecha", en: "no dates")
        }
        return "\(noun), \(idle) \(value)"
    }
}

// MARK: - Footer sources (S2)

/// One panel data source, aggregated over every tracked project in the footer.
public enum ConsoleSource: Hashable, Sendable, CaseIterable {
    case git
    case github
    case engram

    /// Freshness the snapshot holds for this source (S5).
    public func freshness(of snapshot: RepoSnapshot) -> SourceFreshness {
        switch self {
        case .git: return snapshot.git.freshness
        case .github: return snapshot.pr.freshness
        case .engram: return snapshot.activity.freshness
        }
    }

    /// Proper-noun label; the same in both languages.
    public var label: String {
        switch self {
        case .git: return "Git"
        case .github: return "GitHub"
        case .engram: return "Engram"
        }
    }
}

/// Aggregate freshness of one source across every tracked project (S2/L2).
/// The dot is green only when every read is current, orange when some read is
/// not, and hollow when there is no current read at all.
public struct ConsoleSourceRollup: Hashable, Sendable {
    public enum Dot: Hashable, Sendable {
        case current
        case stale
        case none
    }

    public var source: ConsoleSource
    public var currentCount: Int
    public var staleCount: Int
    public var total: Int

    public init(source: ConsoleSource, currentCount: Int, staleCount: Int, total: Int) {
        self.source = source
        self.currentCount = currentCount
        self.staleCount = staleCount
        self.total = total
    }

    public static func make(_ snapshots: [RepoSnapshot],
                            source: ConsoleSource) -> ConsoleSourceRollup {
        var current = 0
        var stale = 0
        for snapshot in snapshots {
            switch source.freshness(of: snapshot) {
            case .current: current += 1
            case .stale: stale += 1
            case .unavailable: break
            }
        }
        return ConsoleSourceRollup(source: source, currentCount: current,
                                   staleCount: stale, total: snapshots.count)
    }

    public var isAllCurrent: Bool { total > 0 && currentCount == total }

    public var dot: Dot {
        if isAllCurrent { return .current }
        if currentCount == 0 && staleCount == 0 { return .none }
        return .stale
    }

    /// Footer text (S2): Git and Engram show how long ago the refresh ran while
    /// every read is current; otherwise every source reports how many projects
    /// were read, so a few local-only repositories never look like a global
    /// outage. GitHub always reports the count because it is often unavailable.
    public func text(lastRefresh: Date?, now: Date, language: AppLanguage) -> String {
        if source != .github, isAllCurrent, let lastRefresh {
            let phrase = Self.relativePhrase(from: lastRefresh, to: now, language: language)
            return "\(source.label) · \(phrase)"
        }
        return "\(source.label) · \(countText(language))"
    }

    private func countText(_ language: AppLanguage) -> String {
        language.pick(es: "\(currentCount) de \(total) leídos",
                      en: "\(currentCount) of \(total) read")
    }

    /// Short relative phrase for the footer's refresh age.
    private static func relativePhrase(from date: Date, to now: Date,
                                       language: AppLanguage) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return language.pick(es: "recién", en: "just now") }
        let minutes = seconds / 60
        if minutes < 60 {
            return language.pick(es: "hace \(minutes) min", en: "\(minutes) min ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            return language.pick(es: "hace \(hours) h", en: "\(hours) h ago")
        }
        let days = hours / 24
        return language.pick(es: "hace \(days) d", en: "\(days) d ago")
    }
}

/// Pull-request section rules of the split console (S7).
public enum ConsolePullRequests {
    /// S7: the "Copy gh auth login" action appears only when the current error
    /// is an authentication one, never for a missing remote.
    public static func showsAuthHint(_ error: String?) -> Bool {
        guard let error else { return false }
        let lowered = error.lowercased()
        return lowered.contains("auth") || lowered.contains("login")
            || lowered.contains("logged")
    }
}
