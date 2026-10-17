import Foundation
import DevControlCore

func ghScannerTests() {
    let now = date(2026, 10, 16)

    // MARK: - GhParser.parseOriginSlug

    checkEqual(GhParser.parseOriginSlug("git@github.com:trueno950/balanceados-pos.git"),
               "trueno950/balanceados-pos", "SSH origin URL parses to slug")
    checkEqual(GhParser.parseOriginSlug("https://github.com/trueno950/xula-sigma.git"),
               "trueno950/xula-sigma", "HTTPS origin URL parses to slug")
    checkEqual(GhParser.parseOriginSlug("https://github.com/trueno950/invitame"),
               "trueno950/invitame", "HTTPS URL without .git suffix")
    checkEqual(GhParser.parseOriginSlug("git@gitlab.com:group/repo.git"),
               "group/repo", "non-github host still yields slug")
    check(GhParser.parseOriginSlug("/local/path/only") == nil, "plain path yields nil")
    check(GhParser.parseOriginSlug("") == nil, "empty URL yields nil")

    // MARK: - GhParser.parseGhDate

    checkEqual(GhParser.parseGhDate("2026-10-10T12:00:00Z"), date(2026, 10, 10),
               "ISO8601 gh date parsed")
    check(GhParser.parseGhDate("2026-10-10T12:00:00.123456Z") != nil,
          "fractional-seconds gh date parsed")

    // MARK: - GhParser.parsePRList

    do {
        let json = """
        [
          {"number": 142, "title": "Fix webhook", "createdAt": "2026-10-02T10:00:00Z",
           "statusCheckRollup": [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FAILURE"}]},
          {"number": 141, "title": "Copy fix", "createdAt": "2026-10-14T10:00:00Z",
           "statusCheckRollup": [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
          {"number": 140, "title": "Vercel failing", "createdAt": "2026-10-05T10:00:00Z",
           "statusCheckRollup": [{"__typename": "StatusContext", "state": "FAILURE"}]},
          {"number": 139, "title": "No checks", "createdAt": "2026-10-14T10:00:00Z",
           "statusCheckRollup": []}
        ]
        """
        let prs = try GhParser.parsePRList(Data(json.utf8), now: now, calendar: cal)
        checkEqual(prs.count, 4, "all PR entries parsed")
        checkEqual(prs[0].number, 142, "PR number preserved")
        checkEqual(prs[0].ageDays, 14, "PR age from createdAt")
        check(prs[0].ciFailing, "CheckRun FAILURE conclusion marks CI failing")
        check(!prs[1].ciFailing, "SUCCESS conclusion not failing")
        check(prs[2].ciFailing, "StatusContext FAILURE state marks CI failing")
        check(!prs[3].ciFailing, "empty rollup not failing")
    } catch {
        check(false, "parsePRList threw: \(error)")
    }

    do {
        let prs = try GhParser.parsePRList(Data("[]".utf8), now: now, calendar: cal)
        check(prs.isEmpty, "empty PR list parses to no PRs")
    } catch {
        check(false, "empty list parse threw: \(error)")
    }

    // MARK: - GhScanner.scan

    do {
        // Happy path: origin remote + pr list.
        let prJSON = """
        [{"number": 7, "title": "Add feature", "createdAt": "2026-10-01T10:00:00Z",
          "statusCheckRollup": [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FAILURE"}]}]
        """
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "remote"]), .success("git@github.com:acme/demo.git\n")),
            (("/opt/homebrew/bin/gh", ["pr"]), .success(prJSON)),
        ])
        let scanner = GhScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", slugOverride: nil,
                                  now: now, calendar: cal)
        check(status.available, "gh scan available when pr list succeeds")
        checkEqual(status.prs.count, 1, "one PR parsed by scanner")
        checkEqual(status.prs[0].number, 7, "scanner PR number")
        check(status.prs[0].ciFailing, "scanner marks failing CI")
        check(status.error == nil, "no error on happy path")
    }

    do {
        // Slug override skips the origin lookup entirely.
        let runner = FakeRunner(outputs: [
            (("/opt/homebrew/bin/gh", ["pr"]), .success("[]")),
        ])
        let scanner = GhScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", slugOverride: "acme/override",
                                  now: now, calendar: cal)
        check(status.available, "slug override scan available")
        check(status.prs.isEmpty, "override scan with no PRs")
    }

    do {
        // gh missing/failing: available false with error, no fabricated PRs.
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "remote"]), .success("git@github.com:acme/demo.git\n")),
            (("/opt/homebrew/bin/gh", ["pr"]), .failure(ScannerError.commandFailed("/opt/homebrew/bin/gh", 1, "gh auth required"))),
        ])
        let scanner = GhScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", slugOverride: nil,
                                  now: now, calendar: cal)
        check(!status.available, "gh failure reports unavailable")
        check(status.prs.isEmpty, "unavailable gh fabricates no PRs")
        check(status.error?.contains("gh") == true, "gh failure surfaces error text")
    }

    do {
        // No origin remote: unavailable but not an error condition.
        let runner = FakeRunner(outputs: [])
        let scanner = GhScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/local-only", slugOverride: nil,
                                  now: now, calendar: cal)
        check(!status.available, "repo without origin is unavailable")
        check(status.error == nil, "missing origin is not an error")
        check(status.prs.isEmpty, "missing origin yields no PRs")
    }

    do {
        // Missing repo path: quiet no-op (GitScanner owns the config error).
        let scanner = GhScanner(runner: FakeRunner(outputs: []))
        let status = scanner.scan(repoPath: "/definitely/missing", slugOverride: nil,
                                  now: now, calendar: cal)
        check(!status.available, "missing path is unavailable")
        check(status.error == nil, "missing path is quiet for gh")
    }

    // MARK: - T9 source freshness and stale retention

    do {
        let prJSON = """
        [{"number": 7, "title": "Add feature", "createdAt": "2026-10-01T10:00:00Z",
          "statusCheckRollup": []}]
        """
        let runner = FakeRunner(outputs: [
            (("/usr/bin/git", ["-C", "/repos/demo", "remote"]), .success("git@github.com:acme/demo.git\n")),
            (("/opt/homebrew/bin/gh", ["pr"]), .success(prJSON)),
        ])
        let scanner = GhScanner(runner: runner, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", slugOverride: nil,
                                  now: now, calendar: cal)
        checkEqual(status.freshness, .current, "a successful gh read is current")
        checkEqual(status.lastReadAt, now, "a successful gh read records its read time")
        check(!status.isStale, "a successful gh read is not stale")
    }

    do {
        // A GitHub failure must never be treated as an empty PR list.
        let readAt = date(2026, 10, 15)
        let previous = PRStatus(
            prs: [PRInfo(number: 14, title: "Fix", ageDays: 2, ciFailing: true)],
            available: true, lastReadAt: readAt)
        let failed = PRStatus(available: false, error: "gh auth required")
        let retained = failed.retainingLastRead(previous)
        checkEqual(retained.prs, previous.prs, "a gh failure keeps the last known PRs")
        check(!retained.prs.isEmpty, "a gh failure is not an empty PR list when data exists")
        checkEqual(retained.available, false, "a gh failure stays reported as unavailable")
        checkEqual(retained.error, "gh auth required",
                   "a gh failure still exposes its current error")
        checkEqual(retained.freshness, .stale, "retained PR data is marked stale")
        checkEqual(retained.lastReadAt, readAt, "retained PR data keeps its read time")
    }

    do {
        let failed = PRStatus(available: false, error: "gh auth required")
        let retained = failed.retainingLastRead(PRStatus(available: false, error: "older failure"))
        checkEqual(retained.prs, [], "a gh failure with no prior success stays empty")
        checkEqual(retained.freshness, .unavailable,
                   "a gh failure with no prior success is unavailable")
    }

    do {
        // A not-applicable source (no origin remote) is unavailable, not stale.
        let scanner = GhScanner(runner: FakeRunner(outputs: []), pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/local-only", slugOverride: nil,
                                  now: now, calendar: cal)
        checkEqual(status.freshness, .unavailable,
                   "a repo without origin reports an unavailable source")
        checkEqual(status.lastReadAt, nil, "an unavailable gh source has no read time")
    }
}
