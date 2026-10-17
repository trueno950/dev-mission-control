import Foundation
import DevControlCore

func engramScannerTests() {
    // MARK: - EngramParser.parseNewestObservation

    do {
        let json = """
        [{"id": 6040, "sync_id": "obs-abc", "session_id": "s1", "type": "decision",
          "title": "PR #14 merged to main", "created_at": "2026-10-16 18:13:49"}]
        """
        let activity = try EngramParser.parseNewestObservation(Data(json.utf8))
        check(activity != nil, "observation list yields activity")
        checkEqual(activity?.title, "PR #14 merged to main", "activity title preserved")
        checkEqual(activity?.date, dateTime(2026, 10, 16, 18, 13, 49), "space-format date parsed as UTC")
    } catch {
        check(false, "newest observation parse threw: \(error)")
    }

    do {
        let json = """
        [{"id": 1, "title": "t", "created_at": "2026-10-16 18:13:49.771365000"}]
        """
        let activity = try EngramParser.parseNewestObservation(Data(json.utf8))
        check(activity != nil, "fractional-seconds date accepted")
        checkEqual(activity?.date, dateTime(2026, 10, 16, 18, 13, 49), "fractional seconds truncated to seconds")
    } catch {
        check(false, "fractional date parse threw: \(error)")
    }

    do {
        let activity = try EngramParser.parseNewestObservation(Data("[]".utf8))
        check(activity == nil, "no observations yields nil activity")
    } catch {
        check(false, "empty observations parse threw: \(error)")
    }

    do {
        let json = """
        [{"id": 2, "title": "only title", "created_at": "not-a-date"}]
        """
        let activity = try EngramParser.parseNewestObservation(Data(json.utf8))
        check(activity != nil, "unparseable date still yields activity")
        checkEqual(activity?.date, Date(timeIntervalSince1970: 0),
                   "unparseable date falls back to epoch (far past, never 'inactive')")
    } catch {
        check(false, "garbage date parse threw: \(error)")
    }

    // MARK: - EngramParser.parseEngramDate

    checkEqual(EngramParser.parseEngramDate("2026-09-20 08:00:00"), dateTime(2026, 9, 20, 8),
               "space-separated engram date")
    check(EngramParser.parseEngramDate("2026-09-20T08:00:00Z") != nil, "ISO8601 accepted")
    check(EngramParser.parseEngramDate("garbage") == nil, "garbage date yields nil")

    // MARK: - Inactivity interplay with AttentionMath

    do {
        // An epoch fallback (garbage date) is 19k+ days old: with available=true
        // that WOULD flag inactivity — verify the fallback stays far past so the
        // panel can show it distinctly. We accept the flag here by contract:
        // garbage dates come only from malformed local data.
        let activity = ActivityInfo(title: "x", date: Date(timeIntervalSince1970: 0))
        let items = AttentionMath.classify(
            snapshot(activity: ActivityStatus(activity: activity, available: true)),
            now: sharedNow, calendar: cal, thresholds: sharedThresholds)
        check(items.first?.kind == .inactiveProject, "epoch-dated activity flags inactivity")
    }

    // MARK: - T9 source freshness and stale retention

    do {
        let readAt = date(2026, 10, 15)
        let previous = ActivityStatus(
            activity: ActivityInfo(title: "last session", date: date(2026, 10, 15)),
            available: true, lastReadAt: readAt)
        let unavailable = ActivityStatus(available: false, error: "Engram unreachable")
        let retained = unavailable.retainingLastRead(previous)
        checkEqual(retained.activity, previous.activity, "an Engram failure keeps the last activity")
        checkEqual(retained.available, false, "an Engram failure stays reported as unavailable")
        checkEqual(retained.error, "Engram unreachable",
                   "an Engram failure still exposes its current error")
        checkEqual(retained.freshness, .stale, "retained activity is marked stale")
        checkEqual(retained.lastReadAt, readAt, "retained activity keeps its read time")
    }

    do {
        let retained = ActivityStatus(available: false, error: "Engram unreachable")
            .retainingLastRead(nil)
        checkEqual(retained.activity, nil,
                   "an Engram failure with no prior success retains nothing")
        checkEqual(retained.freshness, .unavailable,
                   "an Engram failure with no prior success is unavailable")
    }

    do {
        let current = ActivityStatus(activity: ActivityInfo(title: "t", date: date(2026, 10, 16)),
                                     available: true, lastReadAt: date(2026, 10, 16))
        checkEqual(current.freshness, .current, "an available Engram read is current")
    }

    // MARK: - T9 cross-source retention: Git stays usable

    do {
        let previous = RepoSnapshot(
            config: RepoConfig(id: "demo", path: "/repos/demo"),
            git: GitStatus(branch: "main", changes: ChangeCounts(unstaged: 1),
                           lastReadAt: date(2026, 10, 15)),
            pr: PRStatus(prs: [PRInfo(number: 3, title: "T", ageDays: 2, ciFailing: false)],
                         available: true, lastReadAt: date(2026, 10, 15)),
            activity: ActivityStatus(activity: ActivityInfo(title: "old", date: date(2026, 10, 14)),
                                     available: true, lastReadAt: date(2026, 10, 15)))
        let current = RepoSnapshot(
            config: RepoConfig(id: "demo", path: "/repos/demo"),
            git: GitStatus(branch: "main", lastReadAt: date(2026, 10, 16)),
            pr: PRStatus(available: false, error: "gh unavailable"),
            activity: ActivityStatus(available: false, error: "Engram unreachable"))
        let merged = current.retainingLastRead(previous)
        checkEqual(merged.git.freshness, .current,
                   "Git stays current when gh and Engram fail")
        checkEqual(merged.git.lastReadAt, date(2026, 10, 16),
                   "Git keeps its own fresh read time")
        checkEqual(merged.pr.freshness, .stale, "PR data is retained as stale when gh fails")
        checkEqual(merged.pr.prs.count, 1, "stale PR data is retained, not emptied")
        checkEqual(merged.activity.freshness, .stale,
                   "activity is retained as stale when Engram fails")
        checkEqual(merged.activity.activity?.title, "old", "stale activity is retained")
    }

    do {
        let readAt = date(2026, 10, 15)
        let config = RepoConfig(id: "demo", path: "/repos/demo")
        let previous = RepoSnapshot(
            config: config,
            git: GitStatus(branch: "main", changes: ChangeCounts(unstaged: 1),
                           lastReadAt: readAt),
            pr: PRStatus(prs: [PRInfo(number: 7, title: "Fix", ageDays: 1, ciFailing: true)],
                         available: true, lastReadAt: readAt),
            activity: ActivityStatus(activity: ActivityInfo(title: "last", date: readAt),
                                     available: true, lastReadAt: readAt))
        let failedOnce = RepoSnapshot(
            config: config, git: GitStatus(error: "git timeout"),
            pr: PRStatus(available: false, error: "gh unavailable"),
            activity: ActivityStatus(available: false, error: "Engram unavailable"))
            .retainingLastRead(previous)
        let failedTwice = RepoSnapshot(
            config: config, git: GitStatus(error: "git timeout again"),
            pr: PRStatus(available: false, error: "gh still unavailable"),
            activity: ActivityStatus(available: false, error: "Engram still unavailable"))
            .retainingLastRead(failedOnce)
        checkEqual(failedTwice.git.freshness, .stale,
                   "repeated Git failures keep the last successful value stale")
        checkEqual(failedTwice.git.lastReadAt, readAt,
                   "repeated Git failures keep the original read time")
        checkEqual(failedTwice.git.branch, "main",
                   "repeated Git failures keep the last successful branch")
        checkEqual(failedTwice.pr.freshness, .stale,
                   "repeated gh failures keep the last successful PRs stale")
        checkEqual(failedTwice.pr.prs.count, 1,
                   "repeated gh failures do not erase the last successful PR")
        checkEqual(failedTwice.pr.lastReadAt, readAt,
                   "repeated gh failures keep the original read time")
        checkEqual(failedTwice.activity.freshness, .stale,
                   "repeated Engram failures keep the last successful activity stale")
        checkEqual(failedTwice.activity.activity?.title, "last",
                   "repeated Engram failures do not erase the last activity")
        checkEqual(failedTwice.activity.lastReadAt, readAt,
                   "repeated Engram failures keep the original read time")
    }
}
