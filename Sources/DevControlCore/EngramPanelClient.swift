import Foundation

public struct EngramPanelClient: Sendable {
    public let serverBase: URL
    private let session: URLSession

    public init(serverBase: URL = URL(string: "http://127.0.0.1:7437")!,
                session: URLSession = EngramScanner.makeSession()) {
        self.serverBase = serverBase
        self.session = session
    }

    public func stats(project: String) async -> EngramRead<EngramProjectStats> {
        await read(path: "/stats", query: ["project": project]) {
            try EngramPanelParser.parseStats($0)
        }
    }

    public func memories(project: String, limit: Int = 20,
                         type: String? = nil) async -> EngramRead<[EngramMemory]> {
        var query = ["project": project, "limit": String(limit)]
        if let type { query["type"] = type }
        return await read(path: "/observations", query: query) {
            try EngramPanelParser.parseMemories($0)
        }
    }

    public func search(query: String, project: String,
                       limit: Int = 20) async -> EngramRead<[EngramMemory]> {
        await read(path: "/search",
                   query: ["q": query, "project": project, "limit": String(limit)]) {
            try EngramPanelParser.parseMemories($0)
        }
    }

    public func sessions(project: String, limit: Int = 10) async -> EngramRead<[EngramSession]> {
        await read(path: "/sessions/recent",
                   query: ["project": project, "limit": String(limit)]) {
            try EngramPanelParser.parseSessions($0)
        }
    }

    public func context(project: String) async -> EngramRead<String> {
        await read(path: "/context", query: ["project": project]) {
            try EngramPanelParser.parseContext($0)
        }
    }

    public func projects() async -> EngramRead<[EngramProjectEntry]> {
        await read(path: "/projects", query: [:]) {
            try EngramPanelParser.parseProjects($0)
        }
    }

    /// One GET. Transport, HTTP-status, and parse failures all produce a fresh
    /// unavailable read instead of an empty value.
    private func read<Value: Hashable & Sendable>(
        path: String, query: [String: String],
        parse: (Data) throws -> Value
    ) async -> EngramRead<Value> {
        guard let url = EngramPanelRequest.url(base: serverBase, path: path, query: query) else {
            return EngramRead<Value>.failed(error: "Invalid Engram URL")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return EngramRead<Value>.failed(error: "Engram returned HTTP \(code)")
            }
            do {
                return EngramRead(value: try parse(data), available: true, lastReadAt: Date())
            } catch {
                return EngramRead<Value>.failed(
                    error: "Engram response could not be parsed: \(error.localizedDescription)")
            }
        } catch {
            return EngramRead<Value>.failed(
                error: "Engram unreachable: \(error.localizedDescription)")
        }
    }
}

/// Composes the plain-text retake block: the current Git state followed by the
/// Engram retake context (S2/S5). Labels follow the requested language;
/// technical terms stay as-is (S6).
public enum RetakeContext {
    public static func compose(repoName: String, repoPath: String, git: GitStatus,
                               engramProject: String, context: EngramRead<String>,
                               language: AppLanguage, now: Date) -> String {
        var lines: [String] = []
        lines.append("# \(language.pick(es: "Contexto para retomar", en: "Retake context")): \(repoName)")
        lines.append("\(language.pick(es: "Ruta", en: "Path")): \(repoPath)")
        lines.append("\(language.pick(es: "Proyecto Engram", en: "Engram project")): \(engramProject)")
        lines.append("\(language.pick(es: "Generado", en: "Generated")): \(timestamp(now))")
        lines.append("")
        lines.append("## \(language.pick(es: "Estado actual de Git", en: "Current Git state"))")
        if git.freshness == .current {
            lines.append("\(language.pick(es: "Rama", en: "Branch")): \(git.branch ?? "HEAD")")
            lines.append("Staged: \(git.changes.staged)")
            lines.append("Unstaged: \(git.changes.unstaged)")
            lines.append("Untracked: \(git.changes.untracked)")
            lines.append("\(language.pick(es: "Conflictos", en: "Conflicts")): \(git.changes.conflicts)")
            lines.append("\(language.pick(es: "Commits sin subir", en: "Unpushed commits")): \(git.unpushedCount)")
            lines.append("Worktrees: \(git.worktrees.count)")
        } else {
            // S5: a Git read that is not current (failed, or a stale value
            // retained from an earlier read) verifies no branch or counters, so
            // they are never printed as if the read had succeeded. Same shape
            // as the Engram section below.
            lines.append(language.pick(es: "Sin información.", en: "No information available."))
            if let error = git.error {
                lines.append("\(language.pick(es: "Error", en: "Error")): \(error)")
            }
        }
        lines.append("")
        lines.append("## \(language.pick(es: "Memoria de Engram", en: "Engram memory"))")
        if context.available, let value = context.value {
            lines.append(value)
        } else {
            lines.append(language.pick(es: "Sin información.", en: "No information available."))
            if let error = context.error {
                lines.append("\(language.pick(es: "Error", en: "Error")): \(error)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Deterministic UTC timestamp so the composed block is stable to compare.
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
