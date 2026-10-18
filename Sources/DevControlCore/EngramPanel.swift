import Foundation

// Read-only client layer for the local Engram HTTP API (S3).
//
// Every request is a GET against a fixed set of paths; the layer never writes
// to Engram, never opens its SQLite database, and never calls a model. A
// failed read is always represented as an unavailable `EngramRead`, never as
// an empty successful value.

/// Real counters reported by `GET /stats?project=X`.
public struct EngramProjectStats: Hashable, Sendable {
    public var sessions: Int
    public var observations: Int
    public var prompts: Int

    public init(sessions: Int = 0, observations: Int = 0, prompts: Int = 0) {
        self.sessions = sessions
        self.observations = observations
        self.prompts = prompts
    }
}

/// One observation returned by `GET /observations` or `GET /search`.
public struct EngramMemory: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Absent on some entries; a missing type is never invented.
    public var type: String?
    public var title: String
    public var content: String
    /// Nil when the server omitted the field or the value could not be parsed;
    /// a bad date is never turned into epoch (S3).
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: Int, type: String? = nil, title: String, content: String,
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One session returned by `GET /sessions/recent`.
public struct EngramSession: Hashable, Sendable, Identifiable {
    public var id: String
    public var startedAt: Date?
    /// Nil while the session is still running.
    public var endedAt: Date?
    public var observationCount: Int

    public init(id: String, startedAt: Date? = nil, endedAt: Date? = nil,
                observationCount: Int = 0) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.observationCount = observationCount
    }
}

/// One registered project from `GET /projects`, with the directories Engram
/// associates with it (S4).
public struct EngramProjectEntry: Hashable, Sendable {
    public var name: String
    public var directories: [String]

    public init(name: String, directories: [String] = []) {
        self.name = name
        self.directories = directories
    }
}

/// Result of one read-only Engram request with its own freshness (S5). A failed
/// read keeps the current error in its own right while a previous value may be
/// retained marked stale.
public struct EngramRead<Value: Hashable & Sendable>: Hashable, Sendable {
    public var value: Value?
    /// Whether the latest read attempt succeeded.
    public var available: Bool
    public var error: String?
    /// When this value was successfully read; nil when never read.
    public var lastReadAt: Date?
    /// True when `value` is retained from an earlier successful read because
    /// the latest attempt failed.
    public var isStale: Bool

    /// Identity, read time, and freshness of this Engram read (S5).
    public var freshness: SourceFreshness {
        isStale ? .stale : (available ? .current : .unavailable)
    }

    public init(value: Value? = nil, available: Bool = false, error: String? = nil,
                lastReadAt: Date? = nil, isStale: Bool = false) {
        self.value = value
        self.available = available
        self.error = error
        self.lastReadAt = lastReadAt
        self.isStale = isStale
    }

    /// A failed read: unavailable, with the reason and no value.
    public static func failed(error: String) -> EngramRead<Value> {
        EngramRead(available: false, error: error)
    }

    /// S5: when the latest read fails after a successful one, keep the last
    /// valid value and read time marked stale while still exposing the current
    /// failure. Mirrors `ActivityStatus.retainingLastRead`.
    public func retainingLastRead(_ previous: EngramRead?) -> EngramRead {
        guard !available, error != nil, let previous,
              previous.freshness != .unavailable else { return self }
        var retained = self
        retained.value = previous.value
        retained.lastReadAt = previous.lastReadAt
        retained.isStale = true
        return retained
    }
}

/// Pure parsers for the verified Engram 3.4.0 response shapes (S3).
public enum EngramPanelParser {
    /// `GET /stats?project=X` → totals for the project.
    public static func parseStats(_ data: Data) throws -> EngramProjectStats {
        struct Payload: Decodable {
            let total_sessions: Int
            let total_observations: Int
            let total_prompts: Int
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return EngramProjectStats(sessions: payload.total_sessions,
                                  observations: payload.total_observations,
                                  prompts: payload.total_prompts)
    }

    /// `GET /observations` and `GET /search` → observation list. The server's
    /// string-typed `revision_count`/`duplicate_count` fields are tolerated by
    /// not decoding them at all.
    public static func parseMemories(_ data: Data) throws -> [EngramMemory] {
        struct Payload: Decodable {
            let id: Int
            let type: String?
            let title: String
            let content: String
            let created_at: String?
            let updated_at: String?
        }
        let payload = try JSONDecoder().decode([Payload].self, from: data)
        return payload.map { entry in
            EngramMemory(id: entry.id, type: entry.type, title: entry.title,
                         content: entry.content,
                         createdAt: entry.created_at.flatMap(EngramParser.parseEngramDate),
                         updatedAt: entry.updated_at.flatMap(EngramParser.parseEngramDate))
        }
    }

    /// `GET /sessions/recent?project=X&limit=N` → recent session list.
    public static func parseSessions(_ data: Data) throws -> [EngramSession] {
        struct Payload: Decodable {
            let id: String
            let started_at: String?
            let ended_at: String?
            let observation_count: Int
        }
        let payload = try JSONDecoder().decode([Payload].self, from: data)
        return payload.map { entry in
            EngramSession(id: entry.id,
                          startedAt: entry.started_at.flatMap(EngramParser.parseEngramDate),
                          endedAt: entry.ended_at.flatMap(EngramParser.parseEngramDate),
                          observationCount: entry.observation_count)
        }
    }

    /// `GET /context?project=X` → the "Memory from Previous Sessions" markdown.
    public static func parseContext(_ data: Data) throws -> String {
        struct Payload: Decodable {
            let context: String
        }
        return try JSONDecoder().decode(Payload.self, from: data).context
    }

    /// `GET /projects` → registered projects with their directories (S4).
    public static func parseProjects(_ data: Data) throws -> [EngramProjectEntry] {
        struct Payload: Decodable {
            struct Entry: Decodable {
                let name: String
                let directories: [String]?
            }
            let projects: [Entry]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.projects.map {
            EngramProjectEntry(name: $0.name, directories: $0.directories ?? [])
        }
    }
}

/// How a local repository maps to an Engram project (S4).
public struct EngramProjectResolution: Hashable, Sendable {
    public var project: String
    /// True only when the project was chosen from a registered directory.
    public var matchedByDirectory: Bool

    public init(project: String, matchedByDirectory: Bool) {
        self.project = project
        self.matchedByDirectory = matchedByDirectory
    }
}

/// Resolves the Engram project for a repository path (S4). Precedence:
/// explicit configuration, then the most specific registered directory, then
/// the repository folder name.
public enum EngramProjectResolver {
    public static func resolve(repoPath: String, entries: [EngramProjectEntry],
                               configuredName: String?) -> EngramProjectResolution {
        if let configuredName,
           !configuredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EngramProjectResolution(project: configuredName, matchedByDirectory: false)
        }

        let repo = normalized(repoPath)
        var best: (directory: String, name: String)?
        for entry in entries {
            for directory in entry.directories {
                let candidate = normalized(directory)
                guard !candidate.isEmpty, isPathComponentPrefix(candidate, of: repo) else {
                    continue
                }
                let isBetter: Bool
                if let current = best {
                    // Longest directory wins; ties break alphabetically.
                    isBetter = candidate.count > current.directory.count
                        || (candidate.count == current.directory.count
                            && candidate < current.directory)
                } else {
                    isBetter = true
                }
                if isBetter { best = (candidate, entry.name) }
            }
        }
        if let best {
            return EngramProjectResolution(project: best.name, matchedByDirectory: true)
        }
        return EngramProjectResolution(project: (repoPath as NSString).lastPathComponent,
                                       matchedByDirectory: false)
    }

    /// Strips trailing slashes so "/a/b/" and "/a/b" are the same directory.
    private static func normalized(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// True when `directory` is `repo` itself or a whole path-component prefix
    /// of it, so `/a/Projects` never matches `/a/Projects-other`.
    private static func isPathComponentPrefix(_ directory: String, of repo: String) -> Bool {
        repo == directory || repo.hasPrefix(directory + "/")
    }
}

/// Builds the read-only request URLs and owns query-value trimming/encoding (S3).
public enum EngramPanelRequest {
    public static func url(base: URL, path: String, query: [String: String]) -> URL? {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        components?.path = path
        let items = query
            .map { key, value in
                URLQueryItem(name: key,
                             value: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .sorted { $0.name < $1.name }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }
}

/// Read-only Engram HTTP client (S3). Each call is a fresh read; a failure is
/// never reported as an empty success.
