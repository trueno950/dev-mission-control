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
            checkEqual(status.worktrees[1].ageDays, 1, "recent worktree age")
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
}
