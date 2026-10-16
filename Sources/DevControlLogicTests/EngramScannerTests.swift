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
}
