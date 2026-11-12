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

/// Split console panel rules (S2/S3/S6): sidebar grouping, filter, ordering and
/// selection fallback, the worktree state pill, the grouped clean-worktree
/// headline, and the footer's per-source aggregate.
func splitConsolePanelTests() {
    let now = dateTime(2026, 11, 11, 18, 0)
    let readAt = now

    func repo(_ id: String,
              git: GitStatus = GitStatus(),
              pr: PRStatus = PRStatus(),
              activity: ActivityStatus = ActivityStatus(),
              isPaused: Bool = false) -> RepoSnapshot {
        RepoSnapshot(config: RepoConfig(id: id, path: "/tmp/\(id)", isPaused: isPaused),
                     git: git, pr: pr, activity: activity)
    }

    func row(_ snap: RepoSnapshot) -> ConsoleProjectRow {
        ConsoleProjectRow(snapshot: snap, items: AttentionMath.classify(
            snap, now: now, calendar: cal, thresholds: sharedThresholds, language: .english))
    }

    // MARK: - Sidebar rows

    do {
        let conflicted = row(repo("alpha", git: GitStatus(changes: ChangeCounts(conflicts: 2),
                                                         lastReadAt: readAt)))
        checkEqual(conflicted.group, .needsAction, "a conflicted project is a Needs action row")
        checkEqual(conflicted.id, "/tmp/alpha", "a row is identified by its repository path")
        checkEqual(conflicted.name, "alpha", "a row shows the repository id")
        checkEqual(conflicted.severity, .critical, "a row exposes its worst finding severity")

        let memory = ActivityInfo(title: "Audit closed", date: dateTime(2026, 11, 11, 10, 0))
        let commit = LastCommitInfo(shortHash: "d34bec1", subject: "fix",
                                    date: dateTime(2026, 11, 10, 9, 0))
        let touched = row(repo("beta",
                               git: GitStatus(lastReadAt: readAt, lastCommit: commit),
                               activity: ActivityStatus(activity: memory, available: true,
                                                        lastReadAt: readAt)))
        checkEqual(touched.lastTouched, memory.date,
                   "a row's age comes from the newest commit or memory")
        checkEqual(touched.group, .clean, "a project without findings is a Clean row")

        let clean = row(repo("gamma", git: GitStatus(lastReadAt: readAt)))
        checkEqual(clean.severity, nil, "a clean row has no severity")

        let paused = row(repo("delta", git: GitStatus(lastReadAt: readAt), isPaused: true))
        checkEqual(paused.group, .clean, "a paused project without findings stays in Clean")
    }

    // MARK: - Sections

    do {
        let idle = WorktreeInfo(path: "/tmp/idle/.pi/wt/a", name: "a", isDirty: false, ageDays: 15)
        let rows = [
            row(repo("clean", git: GitStatus(lastReadAt: readAt))),
            row(repo("conflict", git: GitStatus(changes: ChangeCounts(conflicts: 1),
                                                lastReadAt: readAt))),
            row(repo("dirty", git: GitStatus(changes: ChangeCounts(unstaged: 2),
                                             lastReadAt: readAt))),
            row(repo("idle", git: GitStatus(worktrees: [idle], lastReadAt: readAt))),
            row(repo("broken", git: GitStatus(error: "not a repository"))),
        ]
        let sections = ConsoleProjectList.sections(rows, filter: "")
        checkEqual(sections.map { $0.group },
                   [.needsAction, .inProgress, .toReview, .noData, .clean],
                   "sections follow the triage group order")
        checkEqual(sections.map { $0.rows.map { $0.name } },
                   [["conflict"], ["dirty"], ["idle"], ["broken"], ["clean"]],
                   "every project lands in its own group")

        let partial = ConsoleProjectList.sections([rows[0], rows[3]], filter: "")
        checkEqual(partial.map { $0.group }, [.toReview, .clean],
                   "empty groups are not listed")
    }

    // MARK: - Filter

    do {
        let rows = [
            row(repo("alpha-sigma", git: GitStatus(lastReadAt: readAt))),
            row(repo("beta", git: GitStatus(lastReadAt: readAt))),
        ]
        checkEqual(ConsoleProjectList.sections(rows, filter: "ALPHA")
                    .flatMap { $0.rows.map { $0.name } },
                   ["alpha-sigma"], "the filter matches ids case-insensitively")
        checkEqual(ConsoleProjectList.sections(rows, filter: "  beta  ")
                    .flatMap { $0.rows.map { $0.name } },
                   ["beta"], "surrounding whitespace is ignored by the filter")
        checkEqual(ConsoleProjectList.sections(rows, filter: "nope").count, 0,
                   "a filter that matches nothing shows no group")
    }

    // MARK: - Ordering inside groups

    do {
        let critical = row(repo("zeta", git: GitStatus(changes: ChangeCounts(conflicts: 1),
                                                       lastReadAt: readAt)))
        let warningA = row(repo("alpha", git: GitStatus(unpushedCount: 3, lastReadAt: readAt)))
        let warningB = row(repo("beta", git: GitStatus(unpushedCount: 1, lastReadAt: readAt)))
        let sections = ConsoleProjectList.sections([warningB, critical, warningA], filter: "")
        checkEqual(sections.first?.rows.map { $0.name }, ["zeta", "alpha", "beta"],
                   "Needs action sorts by worst severity first, then by name")
    }

    do {
        let newest = row(repo("newest", git: GitStatus(
            lastReadAt: readAt,
            lastCommit: LastCommitInfo(shortHash: "a", subject: "s",
                                       date: dateTime(2026, 11, 11, 12, 0)))))
        let older = row(repo("older", git: GitStatus(
            lastReadAt: readAt,
            lastCommit: LastCommitInfo(shortHash: "b", subject: "s",
                                       date: dateTime(2026, 11, 9, 12, 0)))))
        let unknown = row(repo("unknown", git: GitStatus(lastReadAt: readAt)))
        let sections = ConsoleProjectList.sections([unknown, older, newest], filter: "")
        checkEqual(sections.first?.rows.map { $0.name }, ["newest", "older", "unknown"],
                   "the other groups sort by last touched, newest first, unknown age last")
    }

    // MARK: - Selection fallback

    do {
        let rows = [
            row(repo("alpha", git: GitStatus(changes: ChangeCounts(conflicts: 1),
                                             lastReadAt: readAt))),
            row(repo("beta", git: GitStatus(lastReadAt: readAt))),
        ]
        let sections = ConsoleProjectList.sections(rows, filter: "")
        checkEqual(ConsoleProjectList.selection(in: sections, current: "/tmp/beta"), "/tmp/beta",
                   "a selection that still exists is kept")
        checkEqual(ConsoleProjectList.selection(in: sections, current: nil), "/tmp/alpha",
                   "without a selection the first triage row is selected")
        checkEqual(ConsoleProjectList.selection(in: sections, current: "/tmp/gone"), "/tmp/alpha",
                   "a selection for a vanished project falls back to the first triage row")
        checkEqual(ConsoleProjectList.selection(in: [], current: nil), nil,
                   "no rows select nothing")
    }

    // MARK: - Worktree state pill

    do {
        let conflicted = WorktreeInfo(path: "/tmp/r/a", name: "a", isDirty: true, ageDays: 1,
                                      changes: ChangeCounts(conflicts: 2))
        checkEqual(ConsoleWorktreeSummary.state(conflicted, language: .english).text, "2 conflicts",
                   "conflicts are the state pill text in English")
        checkEqual(ConsoleWorktreeSummary.state(conflicted, language: .spanish).text, "2 conflictos",
                   "conflicts are the state pill text in Spanish")
        checkEqual(ConsoleWorktreeSummary.state(conflicted, language: .english).kind, .conflicts,
                   "a conflicted worktree pill is the conflict kind")

        let pending = WorktreeInfo(path: "/tmp/r/b", name: "b", isDirty: true, ageDays: 1,
                                   changes: ChangeCounts(unstaged: 3))
        checkEqual(ConsoleWorktreeSummary.state(pending, language: .english).text, "3 changed",
                   "pending changes are the state pill text in English")
        checkEqual(ConsoleWorktreeSummary.state(pending, language: .spanish).text, "3 cambios",
                   "pending changes are the state pill text in Spanish")
        checkEqual(ConsoleWorktreeSummary.state(pending, language: .english).kind, .pending,
                   "a changed worktree pill is the pending kind")

        let clean = WorktreeInfo(path: "/tmp/r/c", name: "c", isDirty: false, ageDays: 3)
        checkEqual(ConsoleWorktreeSummary.state(clean, language: .english).text, "Clean",
                   "a clean worktree pill reads Clean")
        checkEqual(ConsoleWorktreeSummary.state(clean, language: .spanish).text, "Limpio",
                   "a clean worktree pill reads Limpio in Spanish, never zero counters")
        checkEqual(ConsoleWorktreeSummary.state(clean, language: .english).kind, .clean,
                   "a clean worktree pill is the clean kind")

        let single = WorktreeInfo(path: "/tmp/r/d", name: "d", isDirty: true, ageDays: 1,
                                  changes: ChangeCounts(conflicts: 1))
        checkEqual(ConsoleWorktreeSummary.state(single, language: .spanish).text, "1 conflicto",
                   "one conflict is singular in Spanish")
    }

    // MARK: - Pending change count (sidebar reason)

    do {
        let snap = repo("demo", git: GitStatus(
            worktrees: [
                WorktreeInfo(path: "/tmp/demo/a", name: "a", isDirty: true, ageDays: 0,
                             changes: ChangeCounts(untracked: 1)),
                WorktreeInfo(path: "/tmp/demo/b", name: "b", isDirty: false, ageDays: 0),
            ],
            changes: ChangeCounts(unstaged: 2),
            lastReadAt: readAt))
        checkEqual(ConsoleWorktreeSummary.pendingChangeCount(snap), 3,
                   "pending changes add up across the primary checkout and linked worktrees")
        checkEqual(ConsoleWorktreeSummary.pendingChangeCount(
            repo("demo", git: GitStatus(lastReadAt: readAt))), 0,
                   "a clean project has no pending changes")
    }

    // MARK: - Clean worktree block

    do {
        func idle(_ name: String, _ days: Int, dated: Bool = true) -> WorktreeInfo {
            WorktreeInfo(path: "/tmp/r/\(name)", name: name, isDirty: false, ageDays: days,
                         lastCommitAt: dated ? now.addingTimeInterval(-Double(days) * 86_400) : nil)
        }

        let four = [idle("a", 15), idle("b", 17), idle("c", 16), idle("d", 15)]
        checkEqual(ConsoleWorktreeSummary.cleanHeadline(four, language: .english),
                   "4 clean worktrees, idle 15–17 days",
                   "the clean block headline ranges the idle days in English")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline(four, language: .spanish),
                   "4 worktrees limpios, inactivos 15–17 días",
                   "the clean block headline ranges the idle days in Spanish")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline([idle("a", 16)], language: .english),
                   "1 clean worktree, idle 16 days",
                   "a single idle value is not shown as a range")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline([idle("a", 16)], language: .spanish),
                   "1 worktree limpio, inactivo 16 días",
                   "a single idle value keeps Spanish agreement")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline([idle("a", 3, dated: false),
                                                        idle("b", 9, dated: false)],
                                                       language: .english),
                   "2 clean worktrees, idle no dates",
                   "worktrees without a commit date say no dates")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline([idle("a", 3, dated: false),
                                                        idle("b", 9, dated: false)],
                                                       language: .spanish),
                   "2 worktrees limpios, inactivos sin fecha",
                   "worktrees without a commit date say sin fecha in Spanish")
        checkEqual(ConsoleWorktreeSummary.cleanHeadline([idle("a", 3, dated: false), idle("b", 9)],
                                                       language: .english),
                   "2 clean worktrees, idle 9 days",
                   "only worktrees with a commit date contribute to the idle range")
    }

    // MARK: - Footer source rollup

    do {
        let current = (0..<3).map { repo("r\($0)", git: GitStatus(lastReadAt: readAt)) }
        let git = ConsoleSourceRollup.make(current, source: .git)
        checkEqual(git.dot, .current, "every Git read current is the green dot")
        checkEqual(git.text(lastRefresh: now.addingTimeInterval(-120), now: now,
                            language: .english),
                   "Git · 2 min ago", "an all-current Git source shows its refresh age")
        checkEqual(git.text(lastRefresh: now.addingTimeInterval(-120), now: now,
                            language: .spanish),
                   "Git · hace 2 min", "the refresh age is bilingual")
    }

    do {
        let mixed = [repo("a", git: GitStatus(lastReadAt: readAt)),
                     repo("b", git: GitStatus(error: "boom"))]
        let git = ConsoleSourceRollup.make(mixed, source: .git)
        checkEqual(git.dot, .stale, "a partly unread source is not green")
        checkEqual(git.text(lastRefresh: now, now: now, language: .english),
                   "Git · 1 of 2 read", "a partly read source shows how many were read")
        checkEqual(git.text(lastRefresh: now, now: now, language: .spanish),
                   "Git · 1 de 2 leídos", "the read count is bilingual")
    }

    do {
        let nine = (0..<9).map { index in
            index < 3
                ? repo("r\(index)", pr: PRStatus(available: true, lastReadAt: readAt))
                : repo("r\(index)", pr: PRStatus(error: "no remote"))
        }
        let github = ConsoleSourceRollup.make(nine, source: .github)
        checkEqual(github.text(lastRefresh: now, now: now, language: .english),
                   "GitHub · 3 of 9 read",
                   "GitHub always reports the read count, never a global outage")
        checkEqual(github.text(lastRefresh: now, now: now, language: .spanish),
                   "GitHub · 3 de 9 leídos", "the GitHub read count is bilingual")
        checkEqual(github.dot, .stale, "a partly read GitHub source is not green")
    }

    do {
        let never = [repo("a", git: GitStatus(error: "boom")),
                     repo("b", git: GitStatus(error: "boom"))]
        checkEqual(ConsoleSourceRollup.make(never, source: .git).dot, .none,
                   "a source with no current read is the hollow dot")
        checkEqual(ConsoleSourceRollup.make([], source: .engram).dot, .none,
                   "no tracked project reads nothing")
        checkEqual(ConsoleSourceRollup.make(never, source: .git)
                    .text(lastRefresh: now, now: now, language: .english),
                   "Git · 0 of 2 read", "an unread source reports zero of the total, not a success")

        let connected = [repo("a", activity: ActivityStatus(available: true, lastReadAt: readAt))]
        checkEqual(ConsoleSourceRollup.make(connected, source: .engram).dot, .current,
                   "Engram current is read from the activity source")
    }

    // MARK: - GitHub auth hint

    do {
        check(ConsolePullRequests.showsAuthHint("gh: To get started with GitHub CLI, please run: gh auth login"),
              "an authentication error offers the login command")
        check(ConsolePullRequests.showsAuthHint("You are not LOGGED in"),
              "the login hint is case-insensitive")
        check(!ConsolePullRequests.showsAuthHint("No GitHub remote was found for this repository."),
              "a missing GitHub remote is not an authentication error")
        check(!ConsolePullRequests.showsAuthHint(nil),
              "no current error offers no login command")
    }
}
