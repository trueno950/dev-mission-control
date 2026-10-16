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
}
