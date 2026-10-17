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

/// Counts current findings for a dashboard header. Source freshness is shown
/// separately and is deliberately not counted as an attention notice.
public struct AttentionSummary: Hashable, Sendable {
    public let affectedProjects: Int
    public let notices: Int

    public init(affectedProjects: Int, notices: Int) {
        self.affectedProjects = affectedProjects
        self.notices = notices
    }
}

/// Pure classification of a repository snapshot into attention items.
public enum AttentionMath {
    /// Classifies one snapshot. Items are ordered critical first, then
    /// warnings, then infos; within a severity the order is deterministic
    /// (kind declaration order, then worktree/PR order as given). Messages are
    /// generated in the requested language, defaulting to the system language.
    public static func classify(_ snapshot: RepoSnapshot,
                                now: Date,
                                calendar: Calendar = .current,
                                thresholds: AppConfig,
                                language: AppLanguage = .current) -> [AttentionItem] {
        var items: [AttentionItem] = []

        // Only current reads may establish findings. Failed or stale source
        // data is surfaced through freshness metadata, never as a clean result
        // or a current attention alert.
        if snapshot.git.freshness == .current {
            if snapshot.git.changes.conflicts > 0 {
                let count = snapshot.git.changes.conflicts
                let branch = snapshot.git.branch ?? language.pick(es: "checkout principal", en: "primary checkout")
                let label = language.pick(
                    es: AppLanguage.plural(count, "conflicto de merge", "conflictos de merge"),
                    en: AppLanguage.plural(count, "merge conflict", "merge conflicts"))
                let connector = language.pick(es: "en", en: "on")
                items.append(AttentionItem(kind: .mergeConflict, severity: .critical,
                                           message: "\(count) \(label) \(connector) \(branch)"))
            }

            if snapshot.git.unpushedCount > 0 {
                let branch = snapshot.git.branch ?? "HEAD"
                let message = language.pick(
                    es: "\(snapshot.git.unpushedCount) commit\(snapshot.git.unpushedCount == 1 ? "" : "s") sin subir en \(branch)",
                    en: "\(snapshot.git.unpushedCount) unpushed commit\(snapshot.git.unpushedCount == 1 ? "" : "s") on \(branch)")
                items.append(AttentionItem(kind: .unpushedCommits, severity: .warning,
                                           message: message))
            }

            for worktree in snapshot.git.worktrees {
                if worktree.changes.conflicts > 0 {
                    let count = worktree.changes.conflicts
                    let label = language.pick(
                        es: AppLanguage.plural(count, "conflicto de merge", "conflictos de merge"),
                        en: AppLanguage.plural(count, "merge conflict", "merge conflicts"))
                    let verb = language.pick(es: "tiene", en: "has")
                    items.append(AttentionItem(kind: .mergeConflict, severity: .critical,
                                               message: "Worktree \(worktree.name) \(verb) \(count) \(label)",
                                               worktreePath: worktree.path))
                } else if !snapshot.config.isPaused, !worktree.isDirty,
                          worktree.ageDays > thresholds.staleWorktreeDays {
                    let age = language.pick(
                        es: AppLanguage.plural(worktree.ageDays, "1 día", "\(worktree.ageDays) días"),
                        en: AppLanguage.plural(worktree.ageDays, "1 day", "\(worktree.ageDays) days"))
                    let state = language.pick(es: "inactivo", en: "idle")
                    items.append(AttentionItem(kind: .staleWorktree, severity: .info,
                                               message: "Worktree \(worktree.name) \(state) \(age)",
                                               worktreePath: worktree.path))
                }
            }
        }

        if snapshot.pr.freshness == .current {
            for pr in snapshot.pr.prs {
                if pr.ciFailing {
                    items.append(AttentionItem(kind: .failingCI, severity: .critical,
                                               message: language.pick(es: "PR #\(pr.number) con checks fallidos",
                                                                      en: "PR #\(pr.number) failing CI")))
                }
                if pr.ageDays > thresholds.stalePRDays {
                    let age = language.pick(
                        es: AppLanguage.plural(pr.ageDays, "1 día", "\(pr.ageDays) días"),
                        en: AppLanguage.plural(pr.ageDays, "1 day", "\(pr.ageDays) days"))
                    let opened = language.pick(es: "abierta", en: "open")
                    items.append(AttentionItem(kind: .oldOpenPR, severity: .info,
                                               message: "PR #\(pr.number) \(opened) \(age)"))
                }
            }
        }

        if !snapshot.config.isPaused,
           snapshot.activity.freshness == .current,
           let activity = snapshot.activity.activity {
            let days = daysBetween(activity.date, and: now, calendar: calendar)
            if days > thresholds.inactivityDays {
                let age = language.pick(
                    es: AppLanguage.plural(days, "1 día", "\(days) días"),
                    en: AppLanguage.plural(days, "1 day", "\(days) days"))
                items.append(AttentionItem(kind: .inactiveProject, severity: .info,
                                           message: language.pick(
                                               es: "Sin actividad de Engram durante \(age)",
                                               en: "No Engram activity for \(age)")))
            }
        }

        return sorted(items)
    }

    /// Counts projects with at least one current finding and all visible
    /// findings, including informational notices. Source freshness does not
    /// contribute to either count.
    public static func summaryCounts(_ snapshots: [RepoSnapshot],
                                     now: Date,
                                     calendar: Calendar = .current,
                                     thresholds: AppConfig,
                                     language: AppLanguage = .current) -> AttentionSummary {
        let items = snapshots.map {
            classify($0, now: now, calendar: calendar, thresholds: thresholds,
                     language: language)
        }
        return AttentionSummary(
            affectedProjects: items.filter { !$0.isEmpty }.count,
            notices: items.reduce(0) { $0 + $1.count })
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
