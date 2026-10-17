import Foundation

/// Scans one repository's open pull requests and CI state through the `gh`
/// CLI. When `gh` is missing, unauthenticated, or fails, the result reports
/// `available == false` instead of fabricating findings.
public struct GhScanner {
    private let gh: String
    private let git: String
    private let runner: ProcessRunning
    private let pathExists: (String) -> Bool

    public init(ghPath: String = "/opt/homebrew/bin/gh",
                gitPath: String = "/usr/bin/git",
                runner: ProcessRunning = ProcessRunner(),
                pathExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.gh = ghPath
        self.git = gitPath
        self.runner = runner
        self.pathExists = pathExists
    }

    public func scan(repoPath: String, slugOverride: String?,
                     now: Date = Date(), calendar: Calendar = .current) -> PRStatus {
        guard pathExists(repoPath) else {
            return PRStatus(available: false, error: nil)
        }

        let slug: String?
        if let slugOverride, !slugOverride.isEmpty {
            slug = slugOverride
        } else {
            slug = resolveSlug(repoPath)
        }
        guard let slug else {
            // No origin remote: nothing to query, which is normal for local-only repos.
            return PRStatus(available: false, error: nil)
        }

        do {
            let output = try runner.run(gh, ["pr", "list", "-R", slug, "--state", "open",
                                             "--limit", "20",
                                             "--json", "number,title,createdAt,statusCheckRollup"],
                                        in: nil)
            guard let data = output.data(using: .utf8) else {
                return PRStatus(available: false, error: "gh produced non-UTF8 output")
            }
            let prs = try GhParser.parsePRList(data, now: now, calendar: calendar)
            return PRStatus(prs: prs, available: true, lastReadAt: now)
        } catch {
            return PRStatus(available: false, error: ScannerError.describe(error))
        }
    }

    private func resolveSlug(_ repoPath: String) -> String? {
        guard let url = try? runner.run(git, ["-C", repoPath, "remote", "get-url", "origin"], in: nil)
            else { return nil }
        return GhParser.parseOriginSlug(url)
    }
}

/// Pure parsers and helpers for `gh` output.
public enum GhParser {
    /// Extracts "owner/repo" from an origin URL (SSH or HTTPS form).
    public static func parseOriginSlug(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // HTTPS form: https://github.com/owner/repo.git or .../owner/repo
        if let schemeRange = trimmed.range(of: "://") {
            let rest = trimmed[schemeRange.upperBound...]
            let parts = rest.split(separator: "/", maxSplits: 1,
                                   omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return normalizeSlug(String(parts[1]))
        }

        // SCP-like SSH form: git@github.com:owner/repo.git (colon after the @).
        if let at = trimmed.firstIndex(of: "@"),
           let colon = trimmed.firstIndex(of: ":"), colon > at {
            return normalizeSlug(String(trimmed[trimmed.index(after: colon)...]))
        }
        return nil
    }

    private static func normalizeSlug(_ raw: String) -> String {
        var slug = raw
        if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
        let parts = slug.split(separator: "/")
        guard parts.count == 2 else { return slug }
        return "\(parts[0])/\(parts[1])"
    }

    /// statusCheckRollup entries are polymorphic: CheckRun carries
    /// status+conclusion, StatusContext carries state.
    private struct RolloutCheck: Decodable {
        let status: String?
        let conclusion: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case status, conclusion, state
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
            state = try container.decodeIfPresent(String.self, forKey: .state)
        }
    }

    private struct PRListEntry: Decodable {
        let number: Int
        let title: String
        let createdAt: String
        let statusCheckRollup: [RolloutCheck]?
    }

    /// Parses `gh pr list --json number,title,createdAt,statusCheckRollup`.
    public static func parsePRList(_ data: Data, now: Date,
                                   calendar: Calendar = .current) throws -> [PRInfo] {
        let entries = try JSONDecoder().decode([PRListEntry].self, from: data)
        return entries.map { entry in
            let ageDays: Int
            if let created = parseGhDate(entry.createdAt) {
                ageDays = max(0, (calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: created),
                    to: calendar.startOfDay(for: now)).day ?? 0))
            } else {
                ageDays = 0
            }
            let failing = (entry.statusCheckRollup ?? []).contains { check in
                check.conclusion?.uppercased() == "FAILURE"
                    || check.state?.uppercased() == "FAILURE"
            }
            return PRInfo(number: entry.number, title: entry.title,
                          ageDays: ageDays, ciFailing: failing)
        }
    }

    /// gh emits ISO8601, sometimes with fractional seconds.
    public static func parseGhDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

extension ScannerError {
    /// Human-readable description for surface in the panel.
    static func describe(_ error: Error) -> String {
        if let scannerError = error as? ScannerError {
            return scannerError.description
        }
        return error.localizedDescription
    }
}
