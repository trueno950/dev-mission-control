import Foundation
import DevControlCore

/// Split console panel: project grouping, primary last commit, short relative
/// age, and the copied worktree cleanup command.
func splitConsoleCoreTests() {
    func group(_ snap: RepoSnapshot) -> ProjectGroup {
        ProjectGrouping.group(snap, items: AttentionMath.classify(
            snap, now: sharedNow, calendar: cal, thresholds: sharedThresholds, language: .english))
    }
    let readAt = sharedNow

    // MARK: - ProjectGrouping

    do {
        let conflict = snapshot(git: GitStatus(changes: ChangeCounts(conflicts: 2), lastReadAt: readAt))
        checkEqual(group(conflict), .needsAction, "merge conflict groups the project under Needs action")

        let unpushed = snapshot(git: GitStatus(unpushedCount: 3, lastReadAt: readAt))
        checkEqual(group(unpushed), .needsAction, "unpushed commits group the project under Needs action")

        let failing = snapshot(git: GitStatus(lastReadAt: readAt),
                               pr: PRStatus(prs: [PRInfo(number: 14, title: "x", ageDays: 1, ciFailing: true)],
                                            available: true, lastReadAt: readAt))
        checkEqual(group(failing), .needsAction, "failing CI groups the project under Needs action")

        let pausedConflict = snapshot(git: GitStatus(changes: ChangeCounts(conflicts: 1), lastReadAt: readAt),
                                      isPaused: true)
        checkEqual(group(pausedConflict), .needsAction, "pausing never hides a conflict")
    }

    do {
        let dirtyPrimary = snapshot(git: GitStatus(changes: ChangeCounts(unstaged: 5), lastReadAt: readAt))
        checkEqual(group(dirtyPrimary), .inProgress,
                   "pending primary changes are informational: In progress, not Needs action")

        let dirtyWorktree = snapshot(git: GitStatus(worktrees: [
            WorktreeInfo(path: "/tmp/demo/wt", name: "wt", isDirty: true, ageDays: 0,
                         changes: ChangeCounts(untracked: 1))
        ], lastReadAt: readAt))
        checkEqual(group(dirtyWorktree), .inProgress, "pending linked-worktree changes group as In progress")

        let dirtyAndUnpushed = snapshot(git: GitStatus(unpushedCount: 1, changes: ChangeCounts(staged: 1),
                                                       lastReadAt: readAt))
        checkEqual(group(dirtyAndUnpushed), .needsAction, "a warning outranks pending changes")
    }

    do {
        let idle = snapshot(git: GitStatus(worktrees: [
            WorktreeInfo(path: "/tmp/demo/.pi/review-units/a", name: "a", isDirty: false, ageDays: 15)
        ], lastReadAt: readAt))
        checkEqual(group(idle), .toReview, "info-only findings group the project under To review")

        checkEqual(group(snapshot(git: GitStatus(lastReadAt: readAt))), .clean,
                   "no findings and no pending changes is Clean")

        let pausedIdle = snapshot(git: GitStatus(worktrees: [
            WorktreeInfo(path: "/tmp/demo/wt", name: "wt", isDirty: false, ageDays: 30)
        ], lastReadAt: readAt), isPaused: true)
        checkEqual(group(pausedIdle), .clean, "a paused project without warnings stays in Clean")
    }

    do {
        let unavailable = snapshot(git: GitStatus(error: "Repository path not found: /tmp/demo"))
        checkEqual(group(unavailable), .noData, "an unavailable Git read is No data, never Clean")

        let stale = snapshot(git: GitStatus(error: "timeout", changes: ChangeCounts(unstaged: 2),
                                            lastReadAt: readAt, isStale: true))
        checkEqual(group(stale), .noData, "stale pending changes are not presented as current In progress")
    }

    do {
        checkEqual(ProjectGroup.allCases, [.needsAction, .inProgress, .toReview, .noData, .clean],
                   "groups are listed in triage order")
    }

    // MARK: - Last touched

    do {
        let commitDate = dateTime(2026, 10, 15, 9)
        let memoryDate = dateTime(2026, 10, 16, 8)
        let both = snapshot(
            git: GitStatus(lastReadAt: readAt,
                           lastCommit: LastCommitInfo(shortHash: "d34bec1", subject: "fix", date: commitDate)),
            activity: ActivityStatus(activity: ActivityInfo(title: "Audit", date: memoryDate),
                                     available: true, lastReadAt: readAt))
        checkEqual(ProjectGrouping.lastTouched(both), memoryDate, "last touched is the newest of commit and memory")

        let commitOnly = snapshot(git: GitStatus(
            lastReadAt: readAt, lastCommit: LastCommitInfo(shortHash: "a", subject: "s", date: commitDate)))
        checkEqual(ProjectGrouping.lastTouched(commitOnly), commitDate, "last touched falls back to the last commit")
        checkEqual(ProjectGrouping.lastTouched(snapshot()), nil, "no commit and no memory: last touched is unknown")
    }

    // MARK: - Primary last commit

    do {
        let commit = GitParser.parseLastCommit("d34bec1\t1792152000\tfix(territory): close the audit\n")
        checkEqual(commit, LastCommitInfo(shortHash: "d34bec1", subject: "fix(territory): close the audit",
                                          date: Date(timeIntervalSince1970: 1_792_152_000)),
                   "last commit parses hash, date and subject")
        checkEqual(GitParser.parseLastCommit("abc\t1792152000\tfeat: a\tb\n")?.subject, "feat: a\tb",
                   "a tab inside the subject is kept")
        checkEqual(GitParser.parseLastCommit(""), nil, "a repository without commits has no last commit")
        checkEqual(GitParser.parseLastCommit("abc\tnot-a-date\tx"), nil, "a malformed date yields no last commit")
    }

    do {
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]), .success("")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("0\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]), .success("worktree /repos/demo\nHEAD abc\nbranch refs/heads/main\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "log", "-1"]), .success("d34bec1\t1792152000\tfix: close\n")),
        ])
        let status = GitScanner(runner: runner, pathExists: { _ in true }).scan(repoPath: "/repos/demo", now: sharedNow, calendar: cal)
        checkEqual(status.lastCommit?.shortHash, "d34bec1", "scan reads the primary checkout's last commit")
        checkEqual(status.lastCommit?.subject, "fix: close", "scan keeps the last commit subject")
    }

    do {
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/empty", "status"]), .success("")),
            (("/usr/bin/git", ["-C", "/repos/empty", "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", "/repos/empty", "worktree"]), .success("worktree /repos/empty\nbranch refs/heads/main\n")),
        ])
        let status = GitScanner(runner: runner, pathExists: { _ in true }).scan(repoPath: "/repos/empty", now: sharedNow, calendar: cal)
        check(status.error == nil, "a failed last-commit read does not fail the Git scan")
        checkEqual(status.lastCommit, nil, "a repository without commits has no last commit")
    }

    do {
        let previous = GitStatus(lastReadAt: readAt,
                                 lastCommit: LastCommitInfo(shortHash: "a", subject: "s", date: readAt))
        let retained = GitStatus(error: "timeout").retainingLastRead(previous)
        checkEqual(retained.lastCommit?.shortHash, "a", "a failed refresh retains the last commit as stale")
    }

    // MARK: - Short relative age

    do {
        let now = dateTime(2026, 11, 11, 18, 0)
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 11, 17, 59, 40), to: now, language: .english), "now",
                   "under a minute reads now")
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 11, 17, 59, 40), to: now, language: .spanish), "ahora",
                   "under a minute reads ahora in Spanish")
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 11, 17, 20), to: now, language: .english), "40m",
                   "minutes read as m")
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 11, 15, 0), to: now, language: .english), "3h",
                   "hours read as h")
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 7, 18, 0), to: now, language: .english), "4d",
                   "days read as d")
        checkEqual(RelativeAge.short(from: dateTime(2026, 10, 21, 18, 0), to: now, language: .english), "3w",
                   "14 days or more read as weeks")
        checkEqual(RelativeAge.short(from: dateTime(2026, 11, 11, 18, 5), to: now, language: .english), "now",
                   "a future date (clock skew) reads now")
    }

    // MARK: - Worktree cleanup command

    do {
        let command = WorktreeCleanup.command(
            repoPath: "/Users/me/Projects/xula sigma",
            worktreePaths: ["/Users/me/Projects/xula sigma/.pi/review-units/a", "/tmp/it's here"])
        checkEqual(command,
                   "git -C '/Users/me/Projects/xula sigma' worktree remove '/Users/me/Projects/xula sigma/.pi/review-units/a'\n"
                   + "git -C '/Users/me/Projects/xula sigma' worktree remove '/tmp/it'\\''s here'",
                   "cleanup command quotes every path for the shell, one line per worktree")
        checkEqual(WorktreeCleanup.command(repoPath: "/r", worktreePaths: []), "",
                   "no worktrees yields an empty command")
    }

    do {
        checkEqual(WorktreeCleanup.commonFolder(
            repoPath: "/r/xula", worktreePaths: ["/r/xula/.pi/review-units/a", "/r/xula/.pi/review-units/b"]),
                   ".pi/review-units", "common folder is relative to the repository")
        checkEqual(WorktreeCleanup.commonFolder(
            repoPath: "/r/xula/", worktreePaths: ["/r/xula/.pi/review-units/a"]),
                   ".pi/review-units", "a trailing slash on the repository path is ignored")
        checkEqual(WorktreeCleanup.commonFolder(
            repoPath: "/r/xula", worktreePaths: ["/r/xula/.pi/review-units/a", "/r/xula/wt/b"]),
                   nil, "worktrees in different folders have no common folder")
        checkEqual(WorktreeCleanup.commonFolder(
            repoPath: "/r/xula", worktreePaths: ["/r/xula-wt/a"]),
                   nil, "a worktree outside the repository has no repository-relative folder")
        checkEqual(WorktreeCleanup.commonFolder(
            repoPath: "/r/xula", worktreePaths: ["/r/xula/a"]),
                   nil, "a worktree directly under the repository root has no folder to ignore")
        checkEqual(WorktreeCleanup.commonFolder(repoPath: "/r/xula", worktreePaths: []),
                   nil, "no worktrees have no common folder")
    }
}

/// Per-repository ignored worktree folders (S6): the owner can silence idle
/// notices for harness-created worktree folders such as `.pi/review-units`.
func ignoredWorktreeFolderTests() {
    // MARK: - Config: backward-compatible decoding and roundtrip

    do {
        let legacy = Data("""
        {"id": "demo", "path": "/tmp/demo", "enabled": true}
        """.utf8)
        do {
            let decoded = try JSONDecoder().decode(RepoConfig.self, from: legacy)
            checkEqual(decoded.ignoredWorktreeFolders, [],
                       "a config without ignored folders decodes to none")
        } catch {
            check(false, "legacy repo config decode threw: \(error)")
        }
    }

    do {
        let json = Data("""
        {"repos": [{"id": "demo", "path": "/tmp/demo",
                    "ignoredWorktreeFolders": [".pi/review-units"]}]}
        """.utf8)
        do {
            let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
            checkEqual(decoded.repos.first?.ignoredWorktreeFolders, [".pi/review-units"],
                       "config file key holds the ignored folders")
        } catch {
            check(false, "ignored folder config decode threw: \(error)")
        }
    }

    do {
        let repo = RepoConfig(id: "demo", path: "/tmp/demo",
                              ignoredWorktreeFolders: [".pi/review-units", "vendor/wt"])
        do {
            let data = try JSONEncoder().encode(repo)
            let text = String(data: data, encoding: .utf8) ?? ""
            check(text.contains("ignoredWorktreeFolders"),
                  "encoded config names the ignored folders key")
            let decoded = try JSONDecoder().decode(RepoConfig.self, from: data)
            checkEqual(decoded.ignoredWorktreeFolders, [".pi/review-units", "vendor/wt"],
                       "ignored folders survive a config roundtrip")
            checkEqual(decoded, repo, "roundtrip preserves the whole repository entry")
        } catch {
            check(false, "ignored folder config roundtrip threw: \(error)")
        }
    }

    // MARK: - ignoresWorktree

    do {
        let repo = RepoConfig(id: "demo", path: "/tmp/demo",
                              ignoredWorktreeFolders: [".pi/review-units"])
        check(repo.ignoresWorktree(at: "/tmp/demo/.pi/review-units/a"),
              "a worktree inside an ignored folder is ignored")
        check(repo.ignoresWorktree(at: "/tmp/demo/.pi/review-units/nested/b"),
              "a worktree deeper inside an ignored folder is ignored")
        check(!repo.ignoresWorktree(at: "/tmp/demo/.pi/review-units"),
              "the ignored folder itself is not a worktree inside it")
        check(!RepoConfig(id: "demo", path: "/tmp/demo", ignoredWorktreeFolders: [".pi/review"])
                .ignoresWorktree(at: "/tmp/demo/.pi/review-units/a"),
              "a folder name that only shares a prefix is not ignored")
        check(!repo.ignoresWorktree(at: "/tmp/demo/.pi/manual/a"),
              "a sibling folder of the ignored folder is not ignored")
        check(!repo.ignoresWorktree(at: "/tmp/demo-wt/.pi/review-units/a"),
              "a worktree outside the repository is not ignored")
        check(!RepoConfig(id: "demo", path: "/tmp/demo")
                .ignoresWorktree(at: "/tmp/demo/.pi/review-units/a"),
              "a repository without ignored folders ignores nothing")
    }

    // MARK: - AttentionMath: suppression and preserved conflicts

    do {
        let config = RepoConfig(id: "demo", path: "/tmp/demo",
                                ignoredWorktreeFolders: [".pi/review-units"])
        let idleIgnored = WorktreeInfo(path: "/tmp/demo/.pi/review-units/a", name: "a",
                                       isDirty: false, ageDays: 15)
        let idleSibling = WorktreeInfo(path: "/tmp/demo/.pi/manual/b", name: "b",
                                       isDirty: false, ageDays: 15)
        let snap = RepoSnapshot(config: config,
                                git: GitStatus(worktrees: [idleIgnored, idleSibling]))
        let items = AttentionMath.classify(snap, now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds, language: .english)
        checkEqual(items.count, 1, "an ignored folder keeps only the sibling's idle notice")
        checkEqual(items.first?.worktreePath, "/tmp/demo/.pi/manual/b",
                   "the surviving idle notice belongs to the non-ignored worktree")
        checkEqual(items.first?.kind, .staleWorktree, "the surviving notice is the idle worktree one")
    }

    do {
        let config = RepoConfig(id: "demo", path: "/tmp/demo",
                                ignoredWorktreeFolders: [".pi/review-units"])
        let conflicted = WorktreeInfo(path: "/tmp/demo/.pi/review-units/a", name: "a",
                                      isDirty: true, ageDays: 1,
                                      changes: ChangeCounts(conflicts: 2))
        let snap = RepoSnapshot(config: config, git: GitStatus(worktrees: [conflicted]))
        let items = AttentionMath.classify(snap, now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds, language: .english)
        checkEqual(items.count, 1, "a merge conflict in an ignored folder is still reported")
        checkEqual(items.first?.kind, .mergeConflict, "ignored folder conflict keeps its kind")
        checkEqual(items.first?.severity, .critical, "ignoring a folder never hides a conflict")
    }

    do {
        // Prior behavior: without ignored folders the idle notice still appears.
        let idle = WorktreeInfo(path: "/tmp/demo/.pi/review-units/a", name: "a",
                                isDirty: false, ageDays: 15)
        let snap = RepoSnapshot(config: RepoConfig(id: "demo", path: "/tmp/demo"),
                                git: GitStatus(worktrees: [idle]))
        let items = AttentionMath.classify(snap, now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds, language: .english)
        checkEqual(items.count, 1, "a repository with no ignored folders still gets the idle notice")
        checkEqual(items.first?.kind, .staleWorktree, "the idle notice keeps its kind")
        checkEqual(items.first?.severity, .info, "the idle notice stays informational")
    }
}
