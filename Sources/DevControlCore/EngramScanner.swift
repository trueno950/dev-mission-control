import Foundation

/// Fetches the last recorded Engram observation for one project from the
/// local Engram HTTP server. Read-only GET, short timeout.
public struct EngramScanner {
    public let serverBase: URL
    private let session: URLSession

    /// Bounded page size for the observations read. The newest entry is the
    /// activity signal; the newest `session_summary` entry within this page is
    /// the saved-summary signal (S19). A summary older than the page is not
    /// fabricated.
    public static let scanLimit = 100

    public init(serverBase: URL = URL(string: "http://127.0.0.1:7437")!,
                session: URLSession = EngramScanner.makeSession()) {
        self.serverBase = serverBase
        self.session = session
    }

    /// Ephemeral session with short timeouts for local requests.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }

    public func scan(project: String) async -> ActivityStatus {
        var components = URLComponents(url: serverBase, resolvingAgainstBaseURL: true)
        components?.path = "/observations"
        components?.queryItems = [
            URLQueryItem(name: "project", value: project),
            URLQueryItem(name: "limit", value: String(EngramScanner.scanLimit))
        ]
        guard let url = components?.url else {
            return ActivityStatus(available: false, error: "Invalid Engram URL")
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return ActivityStatus(available: false,
                                      error: "Engram returned HTTP \(code)")
            }
            let activity = try EngramParser.parseNewestObservation(data)
            // A malformed page must not lose the activity signal; the summary
            // is best-effort within the same bounded page.
            let summary = (try? EngramParser.parseLatestSummary(data)) ?? nil
            return ActivityStatus(activity: activity, summary: summary,
                                  available: true, lastReadAt: Date())
        } catch {
            return ActivityStatus(available: false,
                                  error: "Engram unreachable: \(error.localizedDescription)")
        }
    }
}

/// Pure parser for the `GET /observations?project=X&limit=1` response.
public enum EngramParser {
    /// Parses the observation list and returns the newest entry, or nil when
    /// the project has no observations yet.
    public static func parseNewestObservation(_ data: Data) throws -> ActivityInfo? {
        struct Entry: Decodable {
            let title: String
            let created_at: String
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard let first = entries.first else { return nil }
        guard let date = parseEngramDate(first.created_at) else {
            return ActivityInfo(title: first.title,
                                date: Date(timeIntervalSince1970: 0))
        }
        return ActivityInfo(title: first.title, date: date)
    }

    /// Returns the newest saved session summary (type `session_summary`) in
    /// the page, or nil when the page has none. Entries without a `type`
    /// field are never treated as summaries (S19).
    public static func parseLatestSummary(_ data: Data) throws -> SessionSummaryInfo? {
        struct Entry: Decodable {
            let title: String
            let type: String?
            let created_at: String
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard let entry = entries.first(where: { $0.type == "session_summary" }) else {
            return nil
        }
        guard let date = parseEngramDate(entry.created_at) else {
            return SessionSummaryInfo(title: entry.title,
                                      date: Date(timeIntervalSince1970: 0))
        }
        return SessionSummaryInfo(title: entry.title, date: date)
    }

    /// Engram emits "YYYY-MM-DD HH:MM:SS[.fraction]" (UTC) and sometimes ISO8601.
    public static func parseEngramDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let spaceFormatter = DateFormatter()
        spaceFormatter.locale = Locale(identifier: "en_US_POSIX")
        spaceFormatter.timeZone = TimeZone(identifier: "UTC")
        spaceFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = spaceFormatter.date(from: String(trimmed.prefix(19))) {
            return date
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: trimmed)
    }
}
