import Foundation
import DevControlCore

/// In-memory process runner that replays canned command outputs, so scanner
/// logic is tested without spawning git.
struct FakeRunner: ProcessRunning {
    /// Key: "launchPath arg1 arg2..." prefix-matched by first two args.
    var outputs: [(match: (command: String, args: [String]), result: Result<String, Error>)]

    init(outputs: [(match: (command: String, args: [String]), result: Result<String, Error>)]) {
        self.outputs = outputs
    }

    func run(_ launchPath: String, _ arguments: [String], in directory: String?) throws -> String {
        for entry in outputs where entry.match.command == launchPath {
            let wanted = entry.match.args
            guard arguments.count >= wanted.count else { continue }
            let prefix = Array(arguments.prefix(wanted.count))
            if prefix == wanted {
                switch entry.result {
                case let .success(value): return value
                case let .failure(error): throw error
                }
            }
        }
        throw ScannerError.commandFailed(launchPath, 1, "no canned output for \(arguments)")
    }
}

private func scannerError(_ message: String) -> Error {
    ScannerError.commandFailed("/usr/bin/git", 128, message)
}

func gitScannerTests() {
    let now = date(2026, 10, 16)

    // MARK: - GitParser.countStatusEntries

    checkEqual(GitParser.countStatusEntries(""), 0, "empty porcelain output counts zero")
    checkEqual(GitParser.countStatusEntries(" M a.swift\n"), 1, "single modified file counts one")
    checkEqual(GitParser.countStatusEntries("M  a.swift\n?? new.txt\nR  b.swift\n"), 3,
               "multiple entries each count once")

    // MARK: - GitParser.parseChangeCounts (staged / unstaged / untracked / conflicts)

    do {
        let counts = GitParser.parseChangeCounts("M  a.swift\nA  b.swift\nR  c.swift -> d.swift\n")
        checkEqual(counts.staged, 3, "index-only entries count as staged")
        checkEqual(counts.unstaged, 0, "index-only entries add no unstaged count")
        checkEqual(counts.untracked, 0, "index-only entries add no untracked count")
        checkEqual(counts.conflicts, 0, "index-only entries add no conflict count")
        checkEqual(counts.pendingFiles, 3, "staged entries each count once as a pending file")
    }

    do {
        let counts = GitParser.parseChangeCounts(" M a.swift\n D b.swift\n")
        checkEqual(counts.unstaged, 2, "worktree-only entries count as unstaged")
        checkEqual(counts.staged, 0, "worktree-only entries add no staged count")
        checkEqual(counts.untracked, 0, "worktree-only entries add no untracked count")
        checkEqual(counts.conflicts, 0, "worktree-only entries add no conflict count")
        checkEqual(counts.pendingFiles, 2, "unstaged entries each count once as a pending file")
    }

    do {
        let counts = GitParser.parseChangeCounts("?? new.txt\n?? dir/nested.txt\n")
        checkEqual(counts.untracked, 2, "untracked entries count separately")
        checkEqual(counts.staged, 0, "untracked entries add no staged count")
        checkEqual(counts.unstaged, 0, "untracked entries add no unstaged count")
        checkEqual(counts.conflicts, 0, "untracked entries add no conflict count")
        checkEqual(counts.pendingFiles, 2, "untracked entries each count once as a pending file")
    }

    do {
        let counts = GitParser.parseChangeCounts("UU both.swift\nAA added.swift\nDU deleted.swift\n")
        checkEqual(counts.conflicts, 3, "unmerged entries count as conflicts")
        checkEqual(counts.staged, 0, "conflicts are not also counted as staged")
        checkEqual(counts.unstaged, 0, "conflicts are not also counted as unstaged")
        checkEqual(counts.pendingFiles, 3, "conflicts each count once as a pending file")
        check(counts.hasConflicts, "conflict counts report conflict evidence")
    }

    do {
        let output = """
        M  staged.swift
        RM renamed.swift -> next.swift
         M unstaged.swift
        MM both.swift
        ?? untracked.txt
        UU conflict.swift

        """
        let counts = GitParser.parseChangeCounts(output)
        checkEqual(counts.staged, 3, "mixed output counts index changes once")
        checkEqual(counts.unstaged, 3, "mixed output counts worktree changes once")
        checkEqual(counts.untracked, 1, "mixed output counts untracked files once")
        checkEqual(counts.conflicts, 1, "mixed output counts conflicted files once")
        checkEqual(counts.pendingFiles, 6,
                   "a file staged and then modified again counts as one pending file")
        checkEqual(GitParser.countStatusEntries(output), 6,
                   "legacy entry count matches the normalized pending file count")
    }

    do {
        let counts = GitParser.parseChangeCounts("")
        checkEqual(counts, ChangeCounts.none, "empty porcelain output normalizes to no changes")
    }

    // MARK: - GitParser.parseWorktreeBlocks

    do {
        let output = """
        worktree /repos/demo
        HEAD abc1234
        branch refs/heads/main

        worktree /repos/demo/.atl/final-127
        HEAD def5678
        detached

        worktree /repos/demo/.atl/fix-131
        HEAD 9998887
        branch refs/heads/feature/fix-131

        """
        let blocks = GitParser.parseWorktreeBlocks(output)
        checkEqual(blocks.count, 3, "porcelain worktree list yields one block per worktree")
        check(blocks[0].isMain, "first block is the main worktree")
        checkEqual(blocks[0].branch, "main", "main branch parsed from refs/heads prefix")
        checkEqual(blocks[0].headCommit, "abc1234", "main worktree HEAD parsed")
        checkEqual(blocks[1].path, "/repos/demo/.atl/final-127", "detached worktree path parsed")
        checkEqual(blocks[1].branch, nil, "detached worktree has no branch")
        checkEqual(blocks[1].headCommit, "def5678", "detached worktree HEAD parsed")
        check(!blocks[1].isMain, "linked worktrees are not main")
        checkEqual(blocks[2].path, "/repos/demo/.atl/fix-131", "branch worktree path parsed")
        checkEqual(blocks[2].branch, "feature/fix-131", "nested branch name is preserved")
        checkEqual(blocks[2].headCommit, "9998887", "branch worktree HEAD parsed")
    }

    do {
        let blocks = GitParser.parseWorktreeBlocks("worktree /only/main\nHEAD abc\nbranch refs/heads/main\n")
        checkEqual(blocks.count, 1, "single-worktree repo parses one main block")
        check(blocks[0].isMain, "single block is main")
    }

    // MARK: - GitParser.parseCommitTimestamp

    checkEqual(GitParser.parseCommitTimestamp("1792152000\n"),
               Date(timeIntervalSince1970: 1_792_152_000), "epoch timestamp parsed")
    check(GitParser.parseCommitTimestamp("") == nil, "empty timestamp yields nil")
    check(GitParser.parseCommitTimestamp("not-a-number") == nil, "garbage timestamp yields nil")

    let timestamps = GitParser.parseCommitTimestamps("abc123\t1792152000\ndef456\t1792152060\ninvalid\n")
    checkEqual(timestamps["abc123"], Date(timeIntervalSince1970: 1_792_152_000),
               "batch commit timestamp maps hash to date")
    checkEqual(timestamps["def456"], Date(timeIntervalSince1970: 1_792_152_060),
               "batch parser handles multiple commits")
    checkEqual(timestamps.count, 2, "batch parser ignores malformed rows")

    // MARK: - GitScanner.scan

    do {
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]), .success("M  a.swift\n?? b.txt\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .success("feature/dmc\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("3\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]), .success("worktree /repos/demo\nHEAD abc\nbranch refs/heads/feature/dmc\n")),
        ])
        let scanner = GitScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", now: now, calendar: cal)
        check(status.error == nil, "scan succeeds with canned outputs")
        checkEqual(status.branch, "feature/dmc", "branch from symbolic-ref")
        checkEqual(status.dirtyCount, 2, "dirty count from status porcelain")
        checkEqual(status.unpushedCount, 3, "unpushed count from rev-list")
        check(status.worktrees.isEmpty, "main-only worktree list yields no linked worktrees")
    }

    do {
        // T7: the primary checkout is normalized into the four change categories.
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]),
             .success("M  a.swift\n M b.swift\n?? c.txt\nUU d.swift\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("0\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]),
             .success("worktree /repos/demo\nHEAD abc\nbranch refs/heads/main\n")),
        ])
        let scanner = GitScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", now: now, calendar: cal)
        checkEqual(status.error, nil, "checkout normalization fixture scan succeeds")
        checkEqual(status.changes.staged, 1, "checkout staged count")
        checkEqual(status.changes.unstaged, 1, "checkout unstaged count")
        checkEqual(status.changes.untracked, 1, "checkout untracked count")
        checkEqual(status.changes.conflicts, 1, "checkout conflict count")
        checkEqual(status.dirtyCount, 4, "legacy dirtyCount equals the normalized total")
    }

    do {
        // Detached HEAD: symbolic-ref fails, branch is nil, scan still succeeds.
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]), .success("")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .failure(scannerError("fatal: ref HEAD is not a symbolic ref"))),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("0\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]), .success("worktree /repos/demo\nHEAD abc\ndetached\n")),
        ])
        let scanner = GitScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", now: now, calendar: cal)
        check(status.error == nil, "detached HEAD is not an error")
        check(status.branch == nil, "detached HEAD yields nil branch")
        checkEqual(status.dirtyCount, 0, "clean porcelain counts zero")
    }

    do {
        // Linked worktrees: dirty check and commit age per worktree.
        let mainBranch = "worktree /repos/demo\nHEAD abc\nbranch refs/heads/main\n"
        let linked = """
        \(mainBranch)
        worktree /repos/demo/.atl/final-127
        HEAD def
        detached

        worktree /repos/demo/.atl/fix-131
        HEAD 999
        branch refs/heads/feature/fix-131

        """
        // Age: final-127 last commit 9 days before `now`; fix-131 1 day before.
        let nineDaysAgo = String(Int(now.addingTimeInterval(-9 * 86_400).timeIntervalSince1970))
        let oneDayAgo = String(Int(now.addingTimeInterval(-1 * 86_400).timeIntervalSince1970))

        // FakeRunner matches by arg prefix, but per-worktree calls differ only
        // in a -C directory argument, so use exact full-command matching here.
        struct ExactRunner: ProcessRunning {
            var table: [String: Result<String, Error>]
            func run(_ launchPath: String, _ arguments: [String], in directory: String?) throws -> String {
                let key = arguments.joined(separator: " ")
                guard let result = table[key] else {
                    throw ScannerError.commandFailed(launchPath, 1, "no canned output for \(arguments)")
                }
                switch result {
                case let .success(value): return value
                case let .failure(error): throw error
                }
            }
        }

        let exact = ExactRunner(table: [
            "-C /repos/demo status --porcelain=v1": .success(""),
            "-C /repos/demo symbolic-ref --short HEAD": .success("main\n"),
            "-C /repos/demo rev-list --count @{u}..HEAD": .success("0\n"),
            "-C /repos/demo worktree list --porcelain": .success(linked),
            "-C /repos/demo/.atl/final-127 status --porcelain=v1": .success(""),
            "-C /repos/demo/.atl/fix-131 status --porcelain=v1": .success(" M x.swift\n?? new.txt\nA  z.swift\n"),
            "-C /repos/demo log --no-walk --format=%H%x09%ct def 999":
                .success("def\t\(nineDaysAgo)\n999\t\(oneDayAgo)\n"),
        ])

        let scanner = GitScanner(runner: exact, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", now: now, calendar: cal)
        checkEqual(status.error, nil, "worktree fixture scan succeeds")
        checkEqual(status.worktrees.count, 2, "both linked worktrees scanned")
        if status.worktrees.count >= 2 {
            checkEqual(status.worktrees[0].name, "final-127", "worktree name from path")
            checkEqual(status.worktrees[0].headCommit, "def", "worktree keeps its exact HEAD object ID")
            checkEqual(status.worktrees[0].branch, nil, "detached worktree branch remains nil")
            check(!status.worktrees[0].isDirty, "clean worktree not dirty")
            checkEqual(status.worktrees[0].dirtyCount, 0, "clean worktree has zero changed files")
            checkEqual(status.worktrees[0].ageDays, 9, "worktree age from last commit")
            checkEqual(status.worktrees[0].lastCommitAt,
                       Date(timeIntervalSince1970: TimeInterval(nineDaysAgo)!),
                       "last commit timestamp retained")
            check(status.worktrees[1].isDirty, "dirty worktree detected per worktree")
            checkEqual(status.worktrees[1].dirtyCount, 3, "dirty worktree reports changed file count")
            checkEqual(status.worktrees[1].branch, "feature/fix-131", "worktree branch parsed")
            checkEqual(status.worktrees[1].headCommit, "999", "branch worktree keeps its exact HEAD")
            checkEqual(status.worktrees[1].ageDays, 1, "recent worktree age")
        }
    }

    do {
        // T7: linked worktrees are normalized per worktree, not only per repo.
        let linked = """
        worktree /repos/demo
        HEAD abc
        branch refs/heads/main

        worktree /repos/demo/.atl/w1
        HEAD def
        detached

        """
        let epoch = String(Int(now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970))
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]), .success("")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("0\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]), .success(linked)),
            (("/usr/bin/git", ["-C", "/repos/demo", "log"]), .success("def\t\(epoch)\n")),
            (("/usr/bin/git", ["-C", "/repos/demo/.atl/w1", "status"]),
             .success("M  s.swift\n M u.swift\n?? n.swift\nDD c.swift\n")),
        ])
        let scanner = GitScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", now: now, calendar: cal)
        checkEqual(status.error, nil, "per-worktree normalization fixture scan succeeds")
        checkEqual(status.worktrees.count, 1, "normalization fixture yields one linked worktree")
        if let worktree = status.worktrees.first {
            checkEqual(worktree.changes.staged, 1, "worktree staged count")
            checkEqual(worktree.changes.unstaged, 1, "worktree unstaged count")
            checkEqual(worktree.changes.untracked, 1, "worktree untracked count")
            checkEqual(worktree.changes.conflicts, 1, "worktree conflict count")
            checkEqual(worktree.dirtyCount, 4, "worktree dirtyCount equals the normalized total")
            check(worktree.isDirty, "worktree with pending changes stays dirty")
        } else {
            check(false, "per-worktree normalization fixture: missing worktree")
        }
    }

    do {
        let runner = FakeRunner(outputs: [])
        let scanner = GitScanner(runner: runner)
        let status = scanner.scan(repoPath: "/definitely/missing/path", now: now, calendar: cal)
        check(status.error?.contains("not found") == true, "missing path yields config error")
        check(status.error?.contains("/definitely/missing/path") == true, "config error names the path")
    }

    do {
        // git itself failing (not a repo): scan surfaces the error.
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/notarepo", "status"]), .failure(scannerError("fatal: not a git repository"))),
        ])
        let scanner = GitScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/notarepo", now: now, calendar: cal)
        check(status.error?.contains("not a git repository") == true,
              "git failure surfaces its stderr")
    }

    // MARK: - T9 partial Git failures must not look clean

    do {
        let repoPath = "/repos/demo"
        let worktreePath = "/repos/demo/.atl/locked"
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", repoPath, "status"]), .success("")),
            (("/usr/bin/git", ["-C", repoPath, "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", repoPath, "rev-list"]), .success("0\n")),
            (("/usr/bin/git", ["-C", repoPath, "worktree"]), .success("""
                worktree \(repoPath)
                HEAD abc
                branch refs/heads/main

                worktree \(worktreePath)
                HEAD def
                detached

                """)),
            (("/usr/bin/git", ["-C", repoPath, "log"]), .success("def\t100\n")),
            (("/usr/bin/git", ["-C", worktreePath, "status"]),
             .failure(scannerError("unable to read linked worktree"))),
        ])
        let status = GitScanner(runner: runner, pathExists: { _ in true })
            .scan(repoPath: repoPath, now: now, calendar: cal)
        checkEqual(status.freshness, .unavailable,
                   "a linked-worktree Git error cannot produce a falsely clean repo")
        check(status.error?.contains("unable to read linked worktree") == true,
              "linked-worktree Git failure is surfaced")
    }

    // MARK: - T9 source freshness and stale retention

    do {
        let fresh = GitScanner(runner: FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]), .success("")),
            (("/usr/bin/git", ["-C", "/repos/demo", "symbolic-ref"]), .success("main\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "rev-list"]), .success("1\n")),
            (("/usr/bin/git", ["-C", "/repos/demo", "worktree"]),
             .success("worktree /repos/demo\nHEAD abc\nbranch refs/heads/main\n")),
        ]), pathExists: { _ in true }).scan(repoPath: "/repos/demo", now: now, calendar: cal)
        checkEqual(fresh.freshness, .current, "successful git read is current")
        checkEqual(fresh.lastReadAt, now, "successful git read records its read time")
        check(!fresh.isStale, "successful git read is not stale")
    }

    do {
        let inaccessible = GitScanner(runner: FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "status"]),
             .failure(scannerError("fatal: unable to read repository"))),
        ]), pathExists: { _ in true }).scan(repoPath: "/repos/demo", now: now, calendar: cal)
        checkEqual(inaccessible.freshness, .unavailable,
                   "a failed first git read is unavailable")
        check(inaccessible.lastReadAt == nil, "a failed first git read has no read time")
        check(!inaccessible.isStale, "a failed first git read is not stale")
    }

    do {
        let readAt = date(2026, 10, 15)
        let previous = GitStatus(branch: "main", unpushedCount: 4,
                                 worktrees: [WorktreeInfo(path: "/r/.atl/w", name: "w",
                                                          isDirty: false, ageDays: 3)],
                                 changes: ChangeCounts(unstaged: 2),
                                 lastReadAt: readAt)
        let retained = GitStatus(error: "git timed out").retainingLastRead(previous)
        checkEqual(retained.error, "git timed out", "retained git value keeps the current failure")
        checkEqual(retained.freshness, .stale, "retained git value is marked stale")
        checkEqual(retained.lastReadAt, readAt, "retained git value keeps its read time")
        checkEqual(retained.branch, "main", "retained git value keeps the last branch")
        checkEqual(retained.changes.unstaged, 2, "retained git value keeps the last change counts")
        checkEqual(retained.unpushedCount, 4, "retained git value keeps the last unpushed count")
        checkEqual(retained.worktrees.count, 1, "retained git value keeps the last worktrees")
    }

    do {
        let retained = GitStatus(error: "git timed out").retainingLastRead(nil)
        checkEqual(retained.freshness, .unavailable,
                   "no prior git value leaves the source unavailable")
    }
}
