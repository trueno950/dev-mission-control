import Foundation
import DevControlCore

let memoriesJSON = """
[{"id":6065,"type":"session_summary","title":"Session summary: dev-mission-control","content":"## Goal\\nShip it","created_at":"2026-10-17 04:37:49","updated_at":"2026-10-17 04:37:49","revision_count":"3","duplicate_count":"0"}]
"""

let contextJSON = """
{"context":"## Memory from Previous Sessions\\nSomething learned"}
"""

func engramPanelTests() {
    let base = URL(string: "http://127.0.0.1:7437")!

    // MARK: - Stats parsing (S3)

    do {
        let json = """
        {"total_sessions":5,"total_observations":11,"total_prompts":17,"projects":["dev-mission-control"]}
        """
        let stats = try EngramPanelParser.parseStats(Data(json.utf8))
        checkEqual(stats.sessions, 5, "stats parses total_sessions")
        checkEqual(stats.observations, 11, "stats parses total_observations")
        checkEqual(stats.prompts, 17, "stats parses total_prompts")
    } catch {
        check(false, "stats parse threw: \(error)")
    }

    // MARK: - Memory parsing (S3)

    do {
        // `revision_count`/`duplicate_count` arrive as strings; they are not
        // declared on the decoding struct, so they can never break the read.
        let memories = try EngramPanelParser.parseMemories(Data(memoriesJSON.utf8))
        checkEqual(memories.count, 1, "memory page parses one entry")
        checkEqual(memories.first?.id, 6065, "memory keeps its id")
        checkEqual(memories.first?.type, "session_summary", "memory keeps its type")
        checkEqual(memories.first?.title, "Session summary: dev-mission-control",
                   "memory keeps its title")
        checkEqual(memories.first?.content, "## Goal\nShip it",
                   "memory keeps its full content")
        checkEqual(memories.first?.createdAt, dateTime(2026, 10, 17, 4, 37, 49),
                   "memory created_at parsed as UTC")
        checkEqual(memories.first?.updatedAt, dateTime(2026, 10, 17, 4, 37, 49),
                   "memory updated_at parsed as UTC")
    } catch {
        check(false, "memory parse threw: \(error)")
    }

    do {
        let json = """
        [{"id":1,"title":"legacy","content":"body","created_at":"2026-10-17 04:37:49"}]
        """
        let memories = try EngramPanelParser.parseMemories(Data(json.utf8))
        checkEqual(memories.count, 1, "memory without type still parses")
        checkEqual(memories.first?.type, nil, "missing type stays nil")
        checkEqual(memories.first?.updatedAt, nil, "missing updated_at stays nil")
    } catch {
        check(false, "type-less memory parse threw: \(error)")
    }

    do {
        let json = """
        [{"id":2,"title":"t","content":"c","created_at":"not-a-date","updated_at":"not-a-date"}]
        """
        let memories = try EngramPanelParser.parseMemories(Data(json.utf8))
        checkEqual(memories.count, 1, "unparseable date still yields the memory")
        checkEqual(memories.first?.createdAt, nil, "unparseable created_at is nil, never epoch")
        check(memories.first?.createdAt != Date(timeIntervalSince1970: 0),
              "unparseable date is never fabricated as epoch")
        checkEqual(memories.first?.updatedAt, nil, "unparseable updated_at is nil")
    } catch {
        check(false, "garbage-date memory parse threw: \(error)")
    }

    do {
        let memories = try EngramPanelParser.parseMemories(Data("[]".utf8))
        check(memories.isEmpty, "an empty memory page yields an empty list")
    } catch {
        check(false, "empty memory page parse threw: \(error)")
    }

    // MARK: - Session parsing (S3)

    do {
        let json = """
        [{"id":"01a147ab-cd6b-76cf-966f-13cfe4e28bd8","project":"dev-mission-control","started_at":"2026-10-17 02:23:49.181980000","ended_at":"2026-10-17 03:26:33","observation_count":3}]
        """
        let sessions = try EngramPanelParser.parseSessions(Data(json.utf8))
        checkEqual(sessions.count, 1, "session page parses one entry")
        checkEqual(sessions.first?.id, "01a147ab-cd6b-76cf-966f-13cfe4e28bd8",
                   "session keeps its id")
        checkEqual(sessions.first?.startedAt, dateTime(2026, 10, 17, 2, 23, 49),
                   "session started_at parsed with fractional seconds truncated")
        checkEqual(sessions.first?.endedAt, dateTime(2026, 10, 17, 3, 26, 33),
                   "session ended_at parsed")
        checkEqual(sessions.first?.observationCount, 3, "session keeps its observation count")
    } catch {
        check(false, "session parse threw: \(error)")
    }

    do {
        let json = """
        [{"id":"abc","project":"p","started_at":"2026-10-17 02:23:49","observation_count":1}]
        """
        let sessions = try EngramPanelParser.parseSessions(Data(json.utf8))
        checkEqual(sessions.first?.endedAt, nil, "a session still running has no ended_at")
        checkEqual(sessions.first?.observationCount, 1, "open session keeps its observation count")
    } catch {
        check(false, "open session parse threw: \(error)")
    }

    // MARK: - Context parsing (S3)

    do {
        let context = try EngramPanelParser.parseContext(Data(contextJSON.utf8))
        checkEqual(context, "## Memory from Previous Sessions\nSomething learned",
                   "context returns its markdown verbatim")
    } catch {
        check(false, "context parse threw: \(error)")
    }

    do {
        let failed = try? EngramPanelParser.parseContext(Data("{\"other\":1}".utf8))
        checkEqual(failed, nil, "a context response without the field fails")
    }

    // MARK: - Projects parsing (S3/S4)

    do {
        let json = """
        {"count":31,"projects":[{"name":"dev-mission-control","observation_count":11,"session_count":5,"prompt_count":17,"directories":["/Users/joelmay/Documents/Projects","/Users/joelmay/Documents/Projects/dev-mission-control"]},{"name":"solo","observation_count":0,"session_count":0,"prompt_count":0}]}
        """
        let entries = try EngramPanelParser.parseProjects(Data(json.utf8))
        checkEqual(entries.count, 2, "projects page parses every entry")
        checkEqual(entries.first?.name, "dev-mission-control", "project keeps its name")
        checkEqual(entries.first?.directories.count, 2, "project keeps its directories")
        checkEqual(entries.first?.directories.last, "/Users/joelmay/Documents/Projects/dev-mission-control",
                   "project directories keep their order")
        checkEqual(entries.last?.directories, [], "a project without directories has none")
    } catch {
        check(false, "projects parse threw: \(error)")
    }

    // MARK: - Project resolver precedence (S4)

    let devEntry = EngramProjectEntry(
        name: "dev-mission-control",
        directories: ["/Users/x/Projects/dev-mission-control"])
    let parentEntry = EngramProjectEntry(name: "projects", directories: ["/Users/x/Projects"])

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/dev-mission-control",
            entries: [parentEntry, devEntry], configuredName: "custom-name")
        checkEqual(resolution.project, "custom-name", "explicit configuration wins")
        checkEqual(resolution.matchedByDirectory, false,
                   "explicit configuration does not claim a directory match")
    }

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/dev-mission-control",
            entries: [parentEntry, devEntry], configuredName: nil)
        checkEqual(resolution.project, "dev-mission-control",
                   "the longest directory prefix wins over the parent directory")
        checkEqual(resolution.matchedByDirectory, true,
                   "a directory match is reported as such")
    }

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/rental-car-cancun",
            entries: [devEntry], configuredName: nil)
        checkEqual(resolution.project, "rental-car-cancun",
                   "no directory match falls back to the repository folder name")
        checkEqual(resolution.matchedByDirectory, false,
                   "the folder-name fallback is not a directory match")
    }

    do {
        // The registered directories are the only authoritative match source:
        // an unmatched repository is never assigned to an unrelated project.
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/rental-car-cancun",
            entries: [parentEntry, devEntry], configuredName: nil)
        checkEqual(resolution.project, "projects",
                   "the only matching registered directory wins even when it is the parent")
        checkEqual(resolution.matchedByDirectory, true,
                   "a parent-directory match is still a directory match")
    }

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/dev-mission-control/",
            entries: [parentEntry, devEntry], configuredName: nil)
        checkEqual(resolution.project, "dev-mission-control",
                   "a trailing slash on the repository path is tolerated")

        let directorySlash = EngramProjectEntry(
            name: "dev-mission-control",
            directories: ["/Users/x/Projects/dev-mission-control/"])
        let resolutionTwo = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/dev-mission-control",
            entries: [parentEntry, directorySlash], configuredName: nil)
        checkEqual(resolutionTwo.project, "dev-mission-control",
                   "a trailing slash on a registered directory is tolerated")
    }

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects-other", entries: [parentEntry], configuredName: nil)
        checkEqual(resolution.project, "Projects-other",
                   "a sibling with the same name prefix is not a directory match")
    }

    do {
        let resolution = EngramProjectResolver.resolve(
            repoPath: "/Users/x/Projects/dev-mission-control",
            entries: [parentEntry, devEntry], configuredName: "  ")
        checkEqual(resolution.project, "dev-mission-control",
                   "a blank configured name falls through to directory matching")
    }

    // MARK: - Request builder (S3)

    do {
        let url = EngramPanelRequest.url(
            base: base, path: "/search",
            query: ["q": "hello world & more", "project": "dev-mission-control", "limit": "20"])
        check(url != nil, "search URL builds")
        checkEqual(url?.path, "/search", "search URL keeps its path")
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        checkEqual(components?.queryItems?.first(where: { $0.name == "q" })?.value,
                   "hello world & more", "search round-trips spaces and ampersands")
        checkEqual(components?.queryItems?.first(where: { $0.name == "project" })?.value,
                   "dev-mission-control", "search sends the project")
        checkEqual(components?.queryItems?.first(where: { $0.name == "limit" })?.value,
                   "20", "search sends the limit")
        check(url!.absoluteString.contains("%26"), "the ampersand is percent-encoded")
        check(url!.absoluteString.contains("%20"), "the space is percent-encoded")
    }

    do {
        let url = EngramPanelRequest.url(
            base: base, path: "/observations",
            query: ["project": "p", "limit": "20", "type": "decision"])
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        checkEqual(components?.queryItems?.first(where: { $0.name == "type" })?.value,
                   "decision", "observations includes type when present")

        let without = EngramPanelRequest.url(
            base: base, path: "/observations", query: ["project": "p", "limit": "20"])
        let withoutComponents = URLComponents(url: without!, resolvingAgainstBaseURL: false)
        check(withoutComponents?.queryItems?.contains(where: { $0.name == "type" }) == false,
              "observations omits type when it is not present")
    }

    do {
        let url = EngramPanelRequest.url(
            base: base, path: "/sessions/recent", query: ["project": "p", "limit": "10"])
        checkEqual(url?.path, "/sessions/recent", "sessions URL keeps its path")
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        checkEqual(components?.queryItems?.first(where: { $0.name == "limit" })?.value,
                   "10", "sessions sends the limit")
    }

    do {
        let url = EngramPanelRequest.url(
            base: base, path: "/search", query: ["q": "  padded query  "])
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        checkEqual(components?.queryItems?.first(where: { $0.name == "q" })?.value,
                   "padded query", "query values are trimmed")
    }

    // MARK: - Read freshness and stale retention (S5)

    do {
        let readAt = date(2026, 10, 15)
        let previous = EngramRead<String>(value: "old context", available: true, lastReadAt: readAt)
        let failed = EngramRead<String>.failed(error: "Engram unreachable")
        checkEqual(failed.available, false, "a failed read is unavailable")
        checkEqual(failed.value, nil, "a failed read carries no value")

        let retained = failed.retainingLastRead(previous)
        checkEqual(retained.value, "old context", "a failure keeps the last value")
        checkEqual(retained.lastReadAt, readAt, "a failure keeps the previous read time")
        checkEqual(retained.isStale, true, "the retained value is marked stale")
        checkEqual(retained.error, "Engram unreachable", "the current error stays visible")
        checkEqual(retained.available, false, "a retained read is still reported unavailable")
        checkEqual(retained.freshness, .stale, "a retained read reports stale freshness")

        let noPrevious = failed.retainingLastRead(nil)
        checkEqual(noPrevious.value, nil, "no prior success retains nothing")
        checkEqual(noPrevious.freshness, .unavailable,
                   "a failure with no prior success is unavailable")

        let current = EngramRead<String>(value: "fresh", available: true,
                                         lastReadAt: date(2026, 10, 16))
        checkEqual(current.freshness, .current, "an available read is current")
    }

    do {
        let previous = EngramRead<EngramProjectStats>(
            value: EngramProjectStats(sessions: 1, observations: 2, prompts: 3),
            available: true, lastReadAt: date(2026, 10, 15))
        let retained = EngramRead<EngramProjectStats>.failed(error: "Engram unreachable")
            .retainingLastRead(previous)
        checkEqual(retained.value, EngramProjectStats(sessions: 1, observations: 2, prompts: 3),
                   "stale retention works for non-string values too")
    }

}
