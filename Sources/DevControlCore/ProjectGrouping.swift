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
