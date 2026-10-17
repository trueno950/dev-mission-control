import Foundation

/// Process invocation for one read-only worktree action. Arguments remain
/// discrete so worktree paths are never interpolated into shell commands.
public struct WorktreeActionCommand: Hashable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// Open a worktree folder in a user-selected application through Launch Services.
    public static func openApplication(appPath: String, worktreePath: String) -> Self {
        Self(executable: "/usr/bin/open", arguments: ["-a", appPath, worktreePath])
    }

    /// Open the worktree folder in macOS Terminal through its bundle identifier.
    public static func openTerminal(worktreePath: String) -> Self {
        Self(executable: "/usr/bin/open",
             arguments: ["-b", "com.apple.Terminal", worktreePath])
    }

    /// Show staged and unstaged tracked changes relative to the current commit.
    public static func gitDiff(worktreePath: String) -> Self {
        Self(executable: "/usr/bin/git",
             arguments: ["-C", worktreePath, "diff", "HEAD"])
    }
}

public extension RepoSnapshot {
    /// Returns a unique current PR for a linked worktree only when both its
    /// branch and HEAD object ID match and `gh` supplied a safe HTTPS URL.
    func associatedPullRequest(for worktree: WorktreeInfo) -> PRInfo? {
        guard pr.freshness == .current,
              let branch = worktree.branch,
              let headCommit = worktree.headCommit else { return nil }
        let matches = pr.prs.filter {
            $0.headRefName == branch && $0.headRefOid == headCommit && $0.webURL != nil
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
