import Foundation
import DevControlCore

// Test runner helpers. Each suite lives in its own file and is wired below;
// suites are enabled one per task so every commit keeps the build green.

var failures = 0
var total = 0

// Unbuffered stdout so results survive a fatal crash mid-suite.
setbuf(stdout, nil)

func check(_ condition: Bool, _ label: String) {
    total += 1
    if condition {
        print("ok   \(label)")
    } else {
        failures += 1
        print("FAIL \(label)")
    }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
    total += 1
    if a == b {
        print("ok   \(label)")
    } else {
        failures += 1
        print("FAIL \(label) — got \(a), expected \(b)")
    }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!

func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

let sharedNow = date(2026, 10, 16)
let sharedThresholds = AppConfig(refreshIntervalMinutes: 5, staleWorktreeDays: 7,
                                 stalePRDays: 7, inactivityDays: 14)

func snapshot(git: GitStatus = GitStatus(), pr: PRStatus = PRStatus(),
              activity: ActivityStatus = ActivityStatus()) -> RepoSnapshot {
    RepoSnapshot(config: RepoConfig(id: "demo", path: "/tmp/demo"), git: git,
                 pr: pr, activity: activity)
}

func attentionMathTests() {
    // MARK: Clean repo

    do {
        let items = AttentionMath.classify(snapshot(), now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds)
        check(items.isEmpty, "clean repo produces no attention items")
        check(!AttentionMath.needsAttention(items), "clean repo does not need attention")
    }

    // MARK: Dirty files

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(branch: "main", dirtyCount: 3)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "dirty repo yields one item")
        checkEqual(items.first?.kind, .dirtyFiles, "dirty item kind")
        checkEqual(items.first?.severity, .warning, "dirty item severity")
        checkEqual(items.first?.message, "3 uncommitted files", "dirty item plural message")
    }

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(branch: "main", dirtyCount: 1)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.first?.message, "1 uncommitted file", "dirty item singular message")
    }

    // MARK: Unpushed commits

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(branch: "feat/x", unpushedCount: 2)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.first?.kind, .unpushedCommits, "unpushed item kind")
        checkEqual(items.first?.message, "2 unpushed commits on feat/x", "unpushed message names branch")
    }

    // MARK: Worktrees

    do {
        let dirty = WorktreeInfo(path: "/r/.atl/fix-1", name: "fix-1", isDirty: true, ageDays: 1)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [dirty])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "dirty worktree flagged even when young")
        checkEqual(items.first?.kind, .staleWorktree, "dirty worktree kind")
        checkEqual(items.first?.severity, .warning, "dirty worktree severity")
        checkEqual(items.first?.message, "Worktree fix-1 has uncommitted changes", "dirty worktree message")
    }

    do {
        let old = WorktreeInfo(path: "/r/.atl/final-127", name: "final-127", isDirty: false, ageDays: 9)
        let young = WorktreeInfo(path: "/r/.atl/final-130", name: "final-130", isDirty: false, ageDays: 2)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [young, old])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "only stale clean worktree flagged")
        checkEqual(items.first?.message, "Worktree final-127 idle 9 days", "stale worktree message")
        checkEqual(items.first?.severity, .info, "stale clean worktree is info")
    }

    do {
        let edge = WorktreeInfo(path: "/r/.atl/w", name: "w", isDirty: false, ageDays: 7)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [edge])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "worktree at exact threshold is not stale")
    }

    // MARK: Pull requests

    do {
        let failing = PRInfo(number: 14, title: "Fix", ageDays: 2, ciFailing: true)
        let items = AttentionMath.classify(
            snapshot(pr: PRStatus(prs: [failing], available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "failing CI flagged")
        checkEqual(items.first?.kind, .failingCI, "failing CI kind")
        checkEqual(items.first?.severity, .critical, "failing CI severity")
        checkEqual(items.first?.message, "PR #14 failing CI", "failing CI message")
    }

    do {
        let old = PRInfo(number: 8, title: "Feature", ageDays: 10, ciFailing: false)
        let items = AttentionMath.classify(
            snapshot(pr: PRStatus(prs: [old], available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "old PR flagged")
        checkEqual(items.first?.kind, .oldOpenPR, "old PR kind")
        checkEqual(items.first?.severity, .warning, "old PR severity")
    }

    do {
        let both = PRInfo(number: 8, title: "Feature", ageDays: 10, ciFailing: true)
        let items = AttentionMath.classify(
            snapshot(pr: PRStatus(prs: [both], available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 2, "failing and old PR yield both items")
        checkEqual(items.first?.kind, .failingCI, "critical item sorts first")
    }

    // MARK: Engram inactivity

    do {
        let stale = ActivityInfo(title: "old session", date: date(2026, 9, 20))
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: stale, available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "inactive project flagged")
        checkEqual(items.first?.kind, .inactiveProject, "inactivity kind")
        checkEqual(items.first?.message, "No agent activity for 26 days", "inactivity message counts days")
    }

    do {
        let recent = ActivityInfo(title: "recent", date: date(2026, 10, 14))
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: recent, available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "recently active project not flagged")
    }

    do {
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: nil, available: false)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "unavailable Engram source fabricates no finding")
    }

    do {
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: nil, available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "project with no Engram data at all is not flagged")
    }

    // MARK: Config errors

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(error: "Repository path not found: /tmp/gone")),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "config error yields exactly one item")
        checkEqual(items.first?.kind, .configError, "config error kind")
        checkEqual(items.first?.severity, .critical, "config error severity")
        check(items.first?.message.contains("/tmp/gone") == true, "config error names the path")
    }

    // MARK: Severity ordering

    do {
        let snap = snapshot(
            git: GitStatus(branch: "main", dirtyCount: 2, unpushedCount: 1,
                           worktrees: [WorktreeInfo(path: "/r/.atl/w", name: "w", isDirty: false, ageDays: 30)]),
            pr: PRStatus(prs: [PRInfo(number: 5, title: "T", ageDays: 1, ciFailing: true)], available: true))
        let items = AttentionMath.classify(snap, now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds)
        checkEqual(items.map { $0.severity }, [.critical, .warning, .warning, .info],
                   "items sort critical, warnings, infos")
        checkEqual(items[1].message, "1 unpushed commit on main", "warnings sort by message")
        checkEqual(items[2].message, "2 uncommitted files", "warnings sort by message (2)")
        check(AttentionMath.needsAttention(items), "mixed items need attention")
    }

    // MARK: Severity comparable

    check(AttentionItem.Severity.critical > .warning, "severity comparable critical > warning")
    check(AttentionItem.Severity.warning > .info, "severity comparable warning > info")

    // MARK: RepoConfig helpers

    do {
        let repo = RepoConfig(id: "demo", path: "/Users/x/Projects/demo-repo")
        checkEqual(repo.folderName, "demo-repo", "folderName from path")
        checkEqual(repo.resolvedEngramProject, "demo-repo", "engram project defaults to folder name")
        let custom = RepoConfig(id: "demo", path: "/x/demo-repo", engramProject: "other")
        checkEqual(custom.resolvedEngramProject, "other", "engram project override respected")
    }

    // MARK: AppConfig defaults and clamping

    do {
        let config = AppConfig()
        checkEqual(config.refreshIntervalMinutes, 5, "default refresh interval")
        checkEqual(config.staleWorktreeDays, 7, "default stale worktree days")
        checkEqual(config.stalePRDays, 7, "default stale PR days")
        checkEqual(config.inactivityDays, 14, "default inactivity days")
        check(AppConfig(repos: [], refreshIntervalMinutes: 0).refreshIntervalMinutes == 1,
              "refresh interval clamped to >= 1")
    }

    // MARK: ConfigStore

    do {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dmc-tests-\(UUID().uuidString)")
        let store = try ConfigStore(directory: dir)

        let missing = try store.load()
        check(missing == nil, "load returns nil when config file does not exist")

        var config = AppConfig(repos: [RepoConfig(id: "a", path: "/tmp/a"),
                                       RepoConfig(id: "b", path: "/tmp/b", githubSlug: "o/b")],
                               refreshIntervalMinutes: 10)
        config.staleWorktreeDays = 3
        try store.save(config)
        let loaded = try store.load()
        checkEqual(loaded, config, "config roundtrip preserves repos and thresholds")
        check(FileManager.default.fileExists(atPath: store.fileURL.path), "config file created")
        try? FileManager.default.removeItem(at: dir)
    } catch {
        check(false, "config store test threw: \(error)")
    }
}

// Suites wired per task:
attentionMathTests()
gitScannerTests()
// ghScannerTests()    // T4
// ghScannerTests()    // T4
// engramScannerTests() // T5

print("\n\(total - failures)/\(total) checks passed")
if failures > 0 { exit(1) }
