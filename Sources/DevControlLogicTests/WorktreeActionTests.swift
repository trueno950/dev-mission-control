import Foundation
import DevControlCore

func worktreeActionTests() {
    let worktreePath = "/repos/with spaces/demo"
    let editorPath = "/Applications/Code Editor.app"

    // The editor target is optional and remains backward-compatible with older config files.
    do {
        let config = AppConfig(editorApplicationPath: editorPath)
        checkEqual(config.editorApplicationPath, editorPath,
                   "editor app path is configurable")
        do {
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            checkEqual(decoded.editorApplicationPath, editorPath,
                       "editor app path survives config roundtrip")
        } catch {
            check(false, "editor config roundtrip threw: \(error)")
        }

        let oldConfig = Data("""
        {"repos":[],"refreshIntervalMinutes":5,"staleWorktreeDays":7,"stalePRDays":7,"inactivityDays":14}
        """.utf8)
        do {
            let decoded = try JSONDecoder().decode(AppConfig.self, from: oldConfig)
            checkEqual(decoded.editorApplicationPath, nil,
                       "legacy config without editor path still loads")
        } catch {
            check(false, "legacy config without editor path threw: \(error)")
        }
    }

    // Application and Git invocations keep the selected worktree as one argv entry.
    do {
        let editor = WorktreeActionCommand.openApplication(
            appPath: editorPath, worktreePath: worktreePath)
        checkEqual(editor.executable, "/usr/bin/open", "editor action uses Launch Services")
        checkEqual(editor.arguments, ["-a", editorPath, worktreePath],
                   "editor app and spaced worktree path are separate arguments")

        let terminal = WorktreeActionCommand.openTerminal(worktreePath: worktreePath)
        checkEqual(terminal.executable, "/usr/bin/open", "terminal action uses Launch Services")
        checkEqual(terminal.arguments, ["-b", "com.apple.Terminal", worktreePath],
                   "Terminal bundle id and spaced worktree path are separate arguments")

        let diff = WorktreeActionCommand.gitDiff(worktreePath: worktreePath)
        checkEqual(diff.executable, "/usr/bin/git", "diff uses the Git executable")
        checkEqual(diff.arguments, ["-C", worktreePath, "diff", "HEAD"],
                   "diff targets the selected worktree and includes staged changes")
    }

    // A PR is offered only for one current record matching both branch and HEAD SHA.
    do {
        let worktree = WorktreeInfo(path: worktreePath, name: "demo", isDirty: true,
                                    ageDays: 0, branch: "feature", headCommit: "abc123")
        let exact = PRInfo(number: 42, title: "Feature", ageDays: 1, ciFailing: false,
                           headRefName: "feature", headRefOid: "abc123",
                           url: "https://github.com/acme/demo/pull/42")
        let snapshot = RepoSnapshot(
            config: RepoConfig(id: "demo", path: "/repos/demo"),
            git: GitStatus(worktrees: [worktree]),
            pr: PRStatus(prs: [exact], available: true))
        checkEqual(snapshot.associatedPullRequest(for: worktree)?.number, 42,
                   "exact branch and HEAD identify one PR")

        let wrongHead = PRInfo(number: 43, title: "Other", ageDays: 1, ciFailing: false,
                               headRefName: "feature", headRefOid: "different",
                               url: "https://github.com/acme/demo/pull/43")
        let wrongHeadSnapshot = RepoSnapshot(
            config: snapshot.config, git: snapshot.git,
            pr: PRStatus(prs: [wrongHead], available: true))
        checkEqual(wrongHeadSnapshot.associatedPullRequest(for: worktree), nil,
                   "matching branch without matching HEAD is not enough")

        let duplicateSnapshot = RepoSnapshot(
            config: snapshot.config, git: snapshot.git,
            pr: PRStatus(prs: [exact, exact], available: true))
        checkEqual(duplicateSnapshot.associatedPullRequest(for: worktree), nil,
                   "ambiguous matching PRs are not offered")

        let unsafeURL = PRInfo(number: 44, title: "Unsafe", ageDays: 1, ciFailing: false,
                               headRefName: "feature", headRefOid: "abc123",
                               url: "file:///tmp/not-a-pr")
        let unsafeSnapshot = RepoSnapshot(
            config: snapshot.config, git: snapshot.git,
            pr: PRStatus(prs: [unsafeURL], available: true))
        checkEqual(unsafeSnapshot.associatedPullRequest(for: worktree), nil,
                   "non-HTTPS PR URLs are never offered")

        let staleSnapshot = RepoSnapshot(
            config: snapshot.config, git: snapshot.git,
            pr: PRStatus(prs: [exact], available: false,
                         error: "gh unavailable", isStale: true))
        checkEqual(staleSnapshot.associatedPullRequest(for: worktree), nil,
                   "stale PR data cannot authorize an open action")
    }
}
