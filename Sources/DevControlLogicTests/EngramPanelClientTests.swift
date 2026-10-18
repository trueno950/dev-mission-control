import Foundation
import DevControlCore

/// In-process URL protocol so the client tests exercise real request building
/// and response handling without opening a socket.
final class StubURLProtocol: URLProtocol {
    static var respond: ((URLRequest) -> (Int, Data))?
    static var lastRequestURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequestURL = request.url
        guard let respond = StubURLProtocol.respond else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Builds a client whose requests are answered by `StubURLProtocol`.
func stubEngramClient() -> EngramPanelClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return EngramPanelClient(serverBase: URL(string: "http://127.0.0.1:7437")!,
                             session: URLSession(configuration: config))
}

/// Runs an async operation to completion for the synchronous test runner.
func runAsync<T>(_ operation: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?
    Task {
        result = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return result!
}

func engramPanelClientTests() {
    // MARK: - Client reads through an in-process stub (no network)

    do {
        StubURLProtocol.respond = { _ in (200, Data(memoriesJSON.utf8)) }
        let client = stubEngramClient()
        let read = runAsync { await client.memories(project: "dev-mission-control", limit: 20) }
        checkEqual(read.available, true, "a successful client read is available")
        checkEqual(read.freshness, .current, "a successful client read is current")
        checkEqual(read.value?.count, 1, "the client parses the memory page")
        let components = URLComponents(url: StubURLProtocol.lastRequestURL!,
                                       resolvingAgainstBaseURL: false)
        checkEqual(components?.path, "/observations", "memories reads /observations")
        checkEqual(components?.queryItems?.first(where: { $0.name == "project" })?.value,
                   "dev-mission-control", "memories sends the project")
        checkEqual(components?.queryItems?.first(where: { $0.name == "limit" })?.value,
                   "20", "memories sends the limit")
        check(components?.queryItems?.contains(where: { $0.name == "type" }) == false,
              "memories omits type when it is nil")
    }

    do {
        StubURLProtocol.respond = { _ in (200, Data(memoriesJSON.utf8)) }
        let client = stubEngramClient()
        _ = runAsync { await client.memories(project: "p", type: "decision") }
        let components = URLComponents(url: StubURLProtocol.lastRequestURL!,
                                       resolvingAgainstBaseURL: false)
        checkEqual(components?.queryItems?.first(where: { $0.name == "type" })?.value,
                   "decision", "memories sends type when it is not nil")
    }

    do {
        StubURLProtocol.respond = { _ in (200, Data(memoriesJSON.utf8)) }
        let client = stubEngramClient()
        _ = runAsync { await client.search(query: "hello world & more", project: "p", limit: 5) }
        let components = URLComponents(url: StubURLProtocol.lastRequestURL!,
                                       resolvingAgainstBaseURL: false)
        checkEqual(components?.path, "/search", "search reads /search")
        checkEqual(components?.queryItems?.first(where: { $0.name == "q" })?.value,
                   "hello world & more", "search encodes spaces and ampersands")
    }

    do {
        StubURLProtocol.respond = { _ in (200, Data(contextJSON.utf8)) }
        let client = stubEngramClient()
        let read = runAsync { await client.context(project: "dev-mission-control") }
        checkEqual(read.value, "## Memory from Previous Sessions\nSomething learned",
                   "context returns its markdown")
        checkEqual(URLComponents(url: StubURLProtocol.lastRequestURL!,
                                 resolvingAgainstBaseURL: false)?.path, "/context",
                   "context reads /context")
    }

    do {
        StubURLProtocol.respond = { _ in (200, Data("{\"count\":0,\"projects\":[]}".utf8)) }
        let client = stubEngramClient()
        let read = runAsync { await client.projects() }
        checkEqual(read.value, [], "projects parses an empty project list")
        let components = URLComponents(url: StubURLProtocol.lastRequestURL!,
                                       resolvingAgainstBaseURL: false)
        checkEqual(components?.path, "/projects", "projects reads /projects")
        check(components?.queryItems?.isEmpty ?? true, "projects sends no query")
    }

    do {
        StubURLProtocol.respond = { _ in (500, Data()) }
        let client = stubEngramClient()
        let read = runAsync { await client.stats(project: "dev-mission-control") }
        checkEqual(read.available, false, "an HTTP failure is reported unavailable")
        checkEqual(read.value, nil, "an HTTP failure never fabricates a value")
        check(read.error != nil, "an HTTP failure exposes its error")
        checkEqual(read.freshness, .unavailable,
                   "an HTTP failure with no prior read is unavailable")
    }

    do {
        StubURLProtocol.respond = { _ in (200, Data("not json".utf8)) }
        let client = stubEngramClient()
        let read = runAsync { await client.stats(project: "dev-mission-control") }
        checkEqual(read.available, false, "an unparseable response is a failed read")
        checkEqual(read.value, nil, "an unparseable response never fabricates a value")
        check(read.error != nil, "an unparseable response exposes its error")
    }

    // MARK: - Retake context composer (S2/S5/S6)

    let composerNow = dateTime(2026, 10, 16, 9, 30)
    let composerGit = GitStatus(
        branch: "main", unpushedCount: 2,
        worktrees: [WorktreeInfo(path: "/r/.atl/w", name: "w", isDirty: false, ageDays: 1)],
        changes: ChangeCounts(staged: 1, unstaged: 2, untracked: 3),
        lastReadAt: composerNow)
    let composerContext = EngramRead<String>(
        value: "## Memory from Previous Sessions\nSomething learned",
        available: true, lastReadAt: composerNow)

    do {
        let expected = """
        # Retake context: demo-repo
        Path: /Users/x/Projects/demo-repo
        Engram project: dev-mission-control
        Generated: 2026-10-16 09:30

        ## Current Git state
        Branch: main
        Staged: 1
        Unstaged: 2
        Untracked: 3
        Conflicts: 0
        Unpushed commits: 2
        Worktrees: 1

        ## Engram memory
        ## Memory from Previous Sessions
        Something learned
        """
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: composerContext, language: .english, now: composerNow)
        checkEqual(composed, expected, "english retake context includes Git state and memory")
    }

    do {
        let expected = """
        # Contexto para retomar: demo-repo
        Ruta: /Users/x/Projects/demo-repo
        Proyecto Engram: dev-mission-control
        Generado: 2026-10-16 09:30

        ## Estado actual de Git
        Rama: main
        Staged: 1
        Unstaged: 2
        Untracked: 3
        Conflictos: 0
        Commits sin subir: 2
        Worktrees: 1

        ## Memoria de Engram
        ## Memory from Previous Sessions
        Something learned
        """
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: composerContext, language: .spanish, now: composerNow)
        checkEqual(composed, expected, "spanish retake context localizes every label")
    }

    do {
        let unavailable = EngramRead<String>.failed(error: "Engram unreachable")
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: unavailable, language: .english, now: composerNow)
        check(composed.contains("## Engram memory"), "english unavailable context keeps its section")
        check(composed.contains("No information available."),
              "english unavailable context states there is no information")
        check(composed.contains("Error: Engram unreachable"),
              "english unavailable context exposes the read error")
    }

    do {
        let unavailable = EngramRead<String>.failed(error: "Engram unreachable")
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: unavailable, language: .spanish, now: composerNow)
        check(composed.contains("## Memoria de Engram"),
              "spanish unavailable context keeps its section")
        check(composed.contains("Sin información."),
              "spanish unavailable context states there is no information")
        check(composed.contains("Error: Engram unreachable"),
              "spanish unavailable context exposes the read error")
    }

    do {
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: composerContext, language: .english, now: composerNow)
        check(!composed.contains("No information available."),
              "available context never claims there is no information")
    }

    do {
        // A Git read that failed carries no verified counters, so the composer
        // must not print a branch or counters as if they had been read (S5).
        let failedGit = GitStatus(
            branch: "main",
            unpushedCount: 5,
            worktrees: [WorktreeInfo(path: "/r/w", name: "w", isDirty: true, ageDays: 1)],
            error: "git failed",
            changes: ChangeCounts(staged: 9, unstaged: 8, untracked: 7))
        checkEqual(failedGit.freshness, .unavailable, "the failed Git fixture is unavailable")
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: failedGit, engramProject: "dev-mission-control",
            context: composerContext, language: .english, now: composerNow)
        check(composed.contains("## Current Git state"),
              "a failed Git read keeps its section")
        check(composed.contains("No information available."),
              "a failed Git read states there is no information")
        check(composed.contains("Error: git failed"),
              "a failed Git read exposes the read error")
        check(!composed.contains("Staged: 9"),
              "a failed Git read never prints staged counters")
        check(!composed.contains("Unstaged: 8"),
              "a failed Git read never prints unstaged counters")
        check(!composed.contains("Branch: main"),
              "a failed Git read never prints a branch")
        check(!composed.contains("Worktrees: 1"),
              "a failed Git read never prints worktree counts")
    }

    do {
        // A stale Git value is retained but not current, so the same honesty
        // rule applies: its counters are never presented as freshly read (S5).
        let staleGit = GitStatus(
            branch: "main",
            unpushedCount: 5, error: "git failed",
            changes: ChangeCounts(staged: 9, unstaged: 8, untracked: 7),
            lastReadAt: composerNow, isStale: true)
        checkEqual(staleGit.freshness, .stale, "the stale Git fixture is stale")
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: staleGit, engramProject: "dev-mission-control",
            context: composerContext, language: .spanish, now: composerNow)
        check(composed.contains("## Estado actual de Git"),
              "a stale Git read keeps its section")
        check(composed.contains("Sin información."),
              "a stale Git read states there is no information")
        check(composed.contains("Error: git failed"),
              "a stale Git read exposes the read error")
        check(!composed.contains("Staged: 9"),
              "a stale Git read never prints staged counters")
        check(!composed.contains("Rama: main"),
              "a stale Git read never prints a branch")
    }

    do {
        // Preserve the previous behavior for a current Git read: the honesty
        // rule only applies to reads that are not current.
        let composed = RetakeContext.compose(
            repoName: "demo-repo", repoPath: "/Users/x/Projects/demo-repo",
            git: composerGit, engramProject: "dev-mission-control",
            context: composerContext, language: .english, now: composerNow)
        check(composed.contains("Branch: main"), "a current Git read still prints its branch")
        check(composed.contains("Staged: 1"), "a current Git read still prints its counters")
        check(composed.contains("Worktrees: 1"), "a current Git read still prints its worktrees")
    }

    do {
        // The transport error path (no HTTP response at all, rather than a
        // non-200 status): the read is unavailable with an error and never an
        // empty success, and a previous good value is retained marked stale
        // (S3/S5). The stub fails the request while no responder is installed.
        StubURLProtocol.respond = nil
        let client = stubEngramClient()
        let read = runAsync { await client.memories(project: "dev-mission-control", limit: 5) }
        checkEqual(read.available, false, "a transport failure is not available")
        check(read.value == nil, "a transport failure yields no value")
        check(read.error != nil, "a transport failure exposes its error")
        checkEqual(read.freshness, .unavailable,
                   "a transport failure without a prior value is unavailable")

        let previous = EngramRead<[EngramMemory]>(
            value: [EngramMemory(id: 1, type: "decision", title: "kept",
                                 content: "kept content", createdAt: nil, updatedAt: nil)],
            available: true, error: nil, lastReadAt: composerNow)
        let retained = read.retainingLastRead(previous)
        checkEqual(retained.freshness, .stale,
                   "a transport failure keeps the last good value marked stale")
        checkEqual(retained.value?.count, 1,
                   "a transport failure keeps the last good memories")
        check(retained.error != nil,
              "a transport failure still exposes the current error")
    }

    StubURLProtocol.respond = nil
}
