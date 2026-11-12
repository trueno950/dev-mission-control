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

/// Clipboard text for cleaning up a group of idle review worktrees (S6).
/// The result is a command the owner pastes into a shell, so every path is
/// single-quoted; nothing here is executed by the app.
public enum WorktreeCleanup {
    /// One `git worktree remove` line per worktree, joined by newlines.
    /// An empty list yields an empty command.
    public static func command(repoPath: String, worktreePaths: [String]) -> String {
        worktreePaths
            .map { "git -C \(quoted(repoPath)) worktree remove \(quoted($0))" }
            .joined(separator: "\n")
    }

    /// The repository-relative folder that holds every worktree, when all of
    /// them share exactly one folder strictly inside the repository. Nil when
    /// the worktrees are spread out, sit outside the repository, or live
    /// directly in the repository root (nothing to ignore then).
    public static func commonFolder(repoPath: String, worktreePaths: [String]) -> String? {
        guard !worktreePaths.isEmpty else { return nil }
        let root = (repoPath as NSString).standardizingPath
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var folder: String?
        for path in worktreePaths {
            let standardized = (path as NSString).standardizingPath
            guard standardized.hasPrefix(prefix) else { return nil }
            let relative = String(standardized.dropFirst(prefix.count))
            let parent = (relative as NSString).deletingLastPathComponent
            guard !parent.isEmpty else { return nil }
            if let folder, folder != parent { return nil }
            folder = parent
        }
        return folder
    }

    /// Single-quotes one shell argument, escaping embedded single quotes.
    private static func quoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
