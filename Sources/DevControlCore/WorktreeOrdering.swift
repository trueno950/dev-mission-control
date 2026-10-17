import Foundation

/// Pure triage ordering for linked worktrees (T12/S17): conflicted worktrees
/// first, then worktrees with pending changes, then clean ones. Within a
/// group the order is deterministic: more conflicts/changes first, then name.
public enum WorktreeOrdering {
    /// Ranks a worktree by triage weight: 0 conflicted, 1 changed, 2 clean.
    public static func rank(_ worktree: WorktreeInfo) -> Int {
        if worktree.changes.conflicts > 0 { return 0 }
        if worktree.changes.pendingFiles > 0 { return 1 }
        return 2
    }

    /// Sorts worktrees for the repository detail: conflicts, then changed,
    /// then clean; more conflicts/changes first and name as the tiebreak.
    public static func sortedForTriage(_ worktrees: [WorktreeInfo]) -> [WorktreeInfo] {
        worktrees.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsRank == 0, lhs.changes.conflicts != rhs.changes.conflicts {
                return lhs.changes.conflicts > rhs.changes.conflicts
            }
            if lhsRank == 1, lhs.changes.pendingFiles != rhs.changes.pendingFiles {
                return lhs.changes.pendingFiles > rhs.changes.pendingFiles
            }
            return lhs.name < rhs.name
        }
    }

    /// The clean worktrees of the list, in the triage order.
    public static func cleanWorktrees(_ worktrees: [WorktreeInfo]) -> [WorktreeInfo] {
        sortedForTriage(worktrees).filter { rank($0) == 2 }
    }
}
