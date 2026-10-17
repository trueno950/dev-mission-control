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

func dateTime(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int = 0, _ ss: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d,
                                  hour: hh, minute: mm, second: ss))!
}

let sharedNow = date(2026, 10, 16)
let sharedThresholds = AppConfig(refreshIntervalMinutes: 5, staleWorktreeDays: 7,
                                 stalePRDays: 7, inactivityDays: 14)

func snapshot(git: GitStatus = GitStatus(), pr: PRStatus = PRStatus(),
              activity: ActivityStatus = ActivityStatus(),
              isPaused: Bool = false) -> RepoSnapshot {
    RepoSnapshot(config: RepoConfig(id: "demo", path: "/tmp/demo", isPaused: isPaused),
                 git: git, pr: pr, activity: activity)
}

func attentionMathTests() {
    // MARK: Clean repo

    do {
        let items = AttentionMath.classify(snapshot(), now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds)
        check(items.isEmpty, "clean repo produces no attention items")
        check(!AttentionMath.needsAttention(items), "clean repo does not need attention")
    }

    // MARK: Pending changes are informational

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(branch: "main", dirtyCount: 3)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "pending checkout changes do not create an attention finding")
        check(!AttentionMath.needsAttention(items), "pending checkout changes are not urgent")
    }

    do {
        let changes = ChangeCounts(staged: 1, unstaged: 2, untracked: 1)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [WorktreeInfo(path: "/r/w", name: "w",
                isDirty: true, ageDays: 1, changes: changes)])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "pending worktree changes do not create an attention finding")
        check(!AttentionMath.needsAttention(items), "pending worktree changes are not urgent")
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
        let old = WorktreeInfo(path: "/r/.atl/final-127", name: "final-127", isDirty: false, ageDays: 9)
        let young = WorktreeInfo(path: "/r/.atl/final-130", name: "final-130", isDirty: false, ageDays: 2)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [young, old])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "only stale clean worktree flagged")
        checkEqual(items.first?.message, "Worktree final-127 idle 9 days", "stale worktree message")
        checkEqual(items.first?.severity, .info, "stale clean worktree is info")
        check(!AttentionMath.needsAttention(items), "idle worktree information is not urgent")
    }

    do {
        let conflicted = WorktreeInfo(path: "/r/.atl/fix-1", name: "fix-1", isDirty: true,
                                      ageDays: 1, changes: ChangeCounts(conflicts: 2))
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [conflicted])),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "conflicted worktree creates one finding")
        checkEqual(items.first?.kind, .mergeConflict, "conflicted worktree kind")
        checkEqual(items.first?.severity, .critical, "conflict requires attention")
        checkEqual(items.first?.message, "Worktree fix-1 has 2 merge conflicts", "conflict count is explicit")
        checkEqual(items.first?.worktreePath, "/r/.atl/fix-1", "conflict retains selected worktree path")
    }

    do {
        let conflicted = GitStatus(branch: "main", changes: ChangeCounts(conflicts: 1))
        let items = AttentionMath.classify(snapshot(git: conflicted), now: sharedNow,
                                           calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.first?.kind, .mergeConflict, "primary checkout conflict is detected")
        checkEqual(items.first?.severity, .critical, "primary checkout conflict requires attention")
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
        checkEqual(items.first?.severity, .info, "PR age alone is informational")
        check(!AttentionMath.needsAttention(items), "age alone does not require attention")
    }

    do {
        let staleFailure = PRStatus(
            prs: [PRInfo(number: 14, title: "Fix", ageDays: 2, ciFailing: true)],
            available: false, error: "gh unavailable", lastReadAt: date(2026, 10, 15), isStale: true)
        let items = AttentionMath.classify(
            snapshot(pr: staleFailure), now: sharedNow, calendar: cal,
            thresholds: sharedThresholds)
        check(items.isEmpty, "stale failing CI is not presented as a current finding")
        check(!AttentionMath.needsAttention(items), "stale checks alone do not require current attention")
    }

    do {
        let both = PRInfo(number: 8, title: "Feature", ageDays: 10, ciFailing: true)
        let items = AttentionMath.classify(
            snapshot(pr: PRStatus(prs: [both], available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 2, "failing and old PR yield both items")
        checkEqual(items.first?.kind, .failingCI, "critical item sorts first")
        checkEqual(items.last?.severity, .info, "old PR remains informational alongside failure")
        check(AttentionMath.needsAttention(items), "failing CI still requires attention")
    }

    // MARK: Engram inactivity

    do {
        let stale = ActivityInfo(title: "old session", date: date(2026, 9, 20))
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: stale, available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "inactive project flagged")
        checkEqual(items.first?.kind, .inactiveProject, "inactivity kind")
        checkEqual(items.first?.message, "No Engram activity for 26 days", "inactivity message names its source")
        check(!AttentionMath.needsAttention(items), "inactivity information is not urgent")
    }

    do {
        let stale = ActivityInfo(title: "old session", date: date(2026, 9, 20))
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: stale, available: true), isPaused: true),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "paused project suppresses Engram inactivity notice")
    }

    do {
        let oldWorktree = WorktreeInfo(path: "/r/.atl/old", name: "old", isDirty: false, ageDays: 20)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(worktrees: [oldWorktree]), isPaused: true),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "paused project suppresses idle-clean-worktree notice")
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

    // MARK: Git errors are unavailable data, not attention findings

    do {
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(error: "Repository path not found: /tmp/gone")),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "a Git source error is represented as no information, not a finding")
        check(!AttentionMath.needsAttention(items), "a Git source error is not falsely urgent")
    }

    do {
        let failing = PRInfo(number: 21, title: "Current CI failure", ageDays: 1, ciFailing: true)
        let items = AttentionMath.classify(
            snapshot(git: GitStatus(error: "git timed out"),
                    pr: PRStatus(prs: [failing], available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        checkEqual(items.count, 1, "a Git failure does not hide an independent current check")
        checkEqual(items.first?.kind, .failingCI,
                   "current GitHub evidence remains actionable when Git is unavailable")
    }

    do {
        let staleGit = GitStatus(
            branch: "main", error: "git timeout", changes: ChangeCounts(conflicts: 1),
            lastReadAt: date(2026, 10, 15), isStale: true)
        let staleActivity = ActivityStatus(
            activity: ActivityInfo(title: "old", date: date(2026, 9, 1)),
            available: false, error: "Engram unavailable",
            lastReadAt: date(2026, 10, 15), isStale: true)
        let items = AttentionMath.classify(
            snapshot(git: staleGit, activity: staleActivity),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.isEmpty, "stale Git conflicts and Engram activity do not create current findings")
    }

    // MARK: Severity ordering

    do {
        let snap = snapshot(
            git: GitStatus(branch: "main", dirtyCount: 2, unpushedCount: 1,
                           worktrees: [WorktreeInfo(path: "/r/.atl/w", name: "w", isDirty: false, ageDays: 30)]),
            pr: PRStatus(prs: [PRInfo(number: 5, title: "T", ageDays: 1, ciFailing: true)], available: true))
        let items = AttentionMath.classify(snap, now: sharedNow, calendar: cal,
                                           thresholds: sharedThresholds)
        checkEqual(items.map { $0.severity }, [.critical, .warning, .info],
                   "items sort critical, warning, then information")
        checkEqual(items[1].message, "1 unpushed commit on main", "evidence-based warning is retained")
        checkEqual(items[2].message, "Worktree w idle 30 days", "age-only worktree notice stays informational")
        check(AttentionMath.needsAttention(items), "mixed items need attention")
    }

    // MARK: Severity comparable

    check(AttentionItem.Severity.critical > .warning, "severity comparable critical > warning")
    check(AttentionItem.Severity.warning > .info, "severity comparable warning > info")

    // MARK: RepoConfig helpers

    do {
        let repo = RepoConfig(id: "demo", path: "/Users/x/Projects/demo-repo")
        checkEqual(repo.folderName, "demo-repo", "folderName from path")
        check(!repo.isPaused, "new repository defaults to active")
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
                                       RepoConfig(id: "b", path: "/tmp/b", githubSlug: "o/b",
                                                  isPaused: true)],
                               refreshIntervalMinutes: 10)
        config.staleWorktreeDays = 3
        try store.save(config)
        let loaded = try store.load()
        checkEqual(loaded, config, "config roundtrip preserves repos and thresholds")
        check(loaded?.repos.last?.isPaused == true, "config roundtrip preserves paused state")
        check(FileManager.default.fileExists(atPath: store.fileURL.path), "config file created")
        try? FileManager.default.removeItem(at: dir)
    } catch {
        check(false, "config store test threw: \(error)")
    }

    // MARK: Tolerant decoding (older/partial config files)

    do {
        let minimalJSON = """
        {"repos": [{"id": "demo", "path": "/tmp/demo"}]}
        """
        let decoded = try JSONDecoder().decode(AppConfig.self,
                                               from: Data(minimalJSON.utf8))
        checkEqual(decoded.repos.count, 1, "minimal config decodes repos")
        checkEqual(decoded.repos[0].enabled, true, "omitted enabled defaults to true")
        checkEqual(decoded.repos[0].isPaused, false, "omitted paused defaults to false")
        checkEqual(decoded.refreshIntervalMinutes, 5, "omitted refresh interval falls back to default")
        checkEqual(decoded.staleWorktreeDays, 7, "omitted threshold falls back to default")
    } catch {
        check(false, "tolerant decode test threw: \(error)")
    }
}

// Suites wired per task:
attentionMathTests()
gitScannerTests()
ghScannerTests()
engramScannerTests()
// ghScannerTests()    // T4
// engramScannerTests() // T5

print("\n\(total - failures)/\(total) checks passed")
if failures > 0 { exit(1) }
