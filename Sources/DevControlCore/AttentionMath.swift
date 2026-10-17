import Foundation

/// One finding that puts a repository on the "needs attention" list.
public struct AttentionItem: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case configError
        case mergeConflict
        case dirtyFiles
        case unpushedCommits
        case staleWorktree
        case failingCI
        case oldOpenPR
        case inactiveProject
    }

    public enum Severity: Int, Comparable, Sendable {
        case info = 0
        case warning = 1
        case critical = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var kind: Kind
    public var severity: Severity
    public var message: String
    /// Present for worktree findings so the UI can render safe path actions.
    public var worktreePath: String?

    public init(kind: Kind, severity: Severity, message: String,
                worktreePath: String? = nil) {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.worktreePath = worktreePath
    }

    public var id: String {
        if let worktreePath { return "\(kind)-\(worktreePath)" }
        return "\(kind)-\(message)"
    }
}

/// Pure classification of a repository snapshot into attention items.
public enum AttentionMath {
    /// Classifies one snapshot. Items are ordered critical first, then
    /// warnings, then infos; within a severity the order is deterministic
    /// (kind declaration order, then worktree/PR order as given).
    public static func classify(_ snapshot: RepoSnapshot,
                                now: Date,
                                calendar: Calendar = .current,
                                thresholds: AppConfig) -> [AttentionItem] {
        var items: [AttentionItem] = []

        // Config errors first: a broken path outweighs everything else.
        if let gitError = snapshot.git.error {
            items.append(AttentionItem(kind: .configError, severity: .critical,
                                       message: gitError))
            return sorted(items)
        }

        if snapshot.git.changes.conflicts > 0 {
            let count = snapshot.git.changes.conflicts
            let branch = snapshot.git.branch ?? "primary checkout"
            let label = count == 1 ? "merge conflict" : "merge conflicts"
            items.append(AttentionItem(kind: .mergeConflict, severity: .critical,
                                       message: "\(count) \(label) on \(branch)"))
        }

        if snapshot.git.unpushedCount > 0 {
            let branch = snapshot.git.branch ?? "HEAD"
            items.append(AttentionItem(kind: .unpushedCommits, severity: .warning,
                                       message: "\(snapshot.git.unpushedCount) unpushed commit\(snapshot.git.unpushedCount == 1 ? "" : "s") on \(branch)"))
        }

        for worktree in snapshot.git.worktrees {
            if worktree.changes.conflicts > 0 {
                let count = worktree.changes.conflicts
                let label = count == 1 ? "merge conflict" : "merge conflicts"
                items.append(AttentionItem(kind: .mergeConflict, severity: .critical,
                                           message: "Worktree \(worktree.name) has \(count) \(label)",
                                           worktreePath: worktree.path))
            } else if !snapshot.config.isPaused, !worktree.isDirty,
                      worktree.ageDays > thresholds.staleWorktreeDays {
                items.append(AttentionItem(kind: .staleWorktree, severity: .info,
                                           message: "Worktree \(worktree.name) idle \(worktree.ageDays) days",
                                           worktreePath: worktree.path))
            }
        }

        for pr in snapshot.pr.prs {
            if pr.ciFailing {
                items.append(AttentionItem(kind: .failingCI, severity: .critical,
                                           message: "PR #\(pr.number) failing CI"))
            }
            if pr.ageDays > thresholds.stalePRDays {
                items.append(AttentionItem(kind: .oldOpenPR, severity: .info,
                                           message: "PR #\(pr.number) open \(pr.ageDays) days"))
            }
        }

        if !snapshot.config.isPaused,
           snapshot.activity.available, let activity = snapshot.activity.activity {
            let days = daysBetween(activity.date, and: now, calendar: calendar)
            if days > thresholds.inactivityDays {
                items.append(AttentionItem(kind: .inactiveProject, severity: .info,
                                           message: "No Engram activity for \(days) days"))
            }
        }

        return sorted(items)
    }

    /// Whether the repository has an actionable warning or critical finding.
    /// Informational age notices do not count as a project needing attention.
    public static func needsAttention(_ items: [AttentionItem]) -> Bool {
        items.contains { $0.severity > .info }
    }

    // MARK: - Helpers

    private static func sorted(_ items: [AttentionItem]) -> [AttentionItem] {
        items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.message < rhs.message
        }
    }

    private static func daysBetween(_ start: Date, and end: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
