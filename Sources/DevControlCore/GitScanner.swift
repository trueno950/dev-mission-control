import Foundation

/// Abstraction over external process execution so scanners can be tested
/// with canned outputs.
public protocol ProcessRunning {
    /// Runs a command and returns stdout. Throws on non-zero exit or if the
    /// binary cannot be launched.
    func run(_ launchPath: String, _ arguments: [String],
             in directory: String?) throws -> String
}

/// Real process runner backed by Foundation's `Process`.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ launchPath: String, _ arguments: [String],
                    in directory: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw ScannerError.commandFailed(launchPath, process.terminationStatus,
                                             message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum ScannerError: Error, CustomStringConvertible {
    case commandFailed(String, Int32, String)

    public var description: String {
        switch self {
        case let .commandFailed(command, status, message):
            let detail = message.isEmpty ? "no output" : message
            return "\(command) exited \(status): \(detail)"
        }
    }
}

/// Scans one local repository with git: branch, dirty file count, unpushed
/// commit count, and linked worktrees (with dirty state and idle age).
public struct GitScanner {
    private let git: String
    private let runner: ProcessRunning
    private let pathExists: (String) -> Bool

    public init(gitPath: String = "/usr/bin/git",
                runner: ProcessRunning = ProcessRunner(),
                pathExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.git = gitPath
        self.runner = runner
        self.pathExists = pathExists
    }

    public func scan(repoPath: String, now: Date = Date(),
                     calendar: Calendar = .current) -> GitStatus {
        guard pathExists(repoPath) else {
            return GitStatus(error: "Repository path not found: \(repoPath)")
        }

        do {
            let branch = try currentBranch(repoPath)
            let dirtyCount = try dirtyFileCount(repoPath)
            let unpushedCount = unpushedCommitCount(repoPath)
            let worktrees = try scanWorktrees(repoPath, now: now, calendar: calendar)
            return GitStatus(branch: branch, dirtyCount: dirtyCount,
                             unpushedCount: unpushedCount, worktrees: worktrees)
        } catch {
            return GitStatus(error: describe(error, for: repoPath))
        }
    }

    // MARK: - Steps

    private func currentBranch(_ repoPath: String) throws -> String? {
        // Detached HEAD exits non-zero: that is a valid state, not an error.
        let output = try? runner.run(git, ["-C", repoPath, "symbolic-ref", "--short", "HEAD"], in: nil)
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dirtyFileCount(_ repoPath: String) throws -> Int {
        let output = try runner.run(git, ["-C", repoPath, "status", "--porcelain=v1"], in: nil)
        return GitParser.countStatusEntries(output)
    }

    private func unpushedCommitCount(_ repoPath: String) -> Int {
        // No upstream (or other rev-list failure) simply means nothing to push.
        guard let output = try? runner.run(git, ["-C", repoPath, "rev-list", "--count", "@{u}..HEAD"],
                                           in: nil) else { return 0 }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func scanWorktrees(_ repoPath: String, now: Date,
                               calendar: Calendar) throws -> [WorktreeInfo] {
        let output = try runner.run(git, ["-C", repoPath, "worktree", "list", "--porcelain"], in: nil)
        let blocks = GitParser.parseWorktreeBlocks(output)

        var result: [WorktreeInfo] = []
        for block in blocks where !block.isMain {
            let worktreePath = block.path
            let dirty = (try? dirtyFileCount(worktreePath)).map { $0 > 0 } ?? false
            let ageDays: Int
            if let timestamp = lastCommitTimestamp(worktreePath) {
                ageDays = max(0, (calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: timestamp),
                    to: calendar.startOfDay(for: now)).day ?? 0))
            } else {
                ageDays = 0
            }
            result.append(WorktreeInfo(path: worktreePath,
                                       name: (worktreePath as NSString).lastPathComponent,
                                       isDirty: dirty, ageDays: ageDays))
        }
        return result
    }

    private func lastCommitTimestamp(_ directory: String) -> Date? {
        guard let output = try? runner.run(git, ["-C", directory, "log", "-1", "--format=%ct"],
                                           in: nil) else { return nil }
        return GitParser.parseCommitTimestamp(output)
    }

    private func describe(_ error: Error, for repoPath: String) -> String {
        if let scannerError = error as? ScannerError {
            return scannerError.description
        }
        return "git scan failed for \(repoPath): \(error.localizedDescription)"
    }
}

/// Pure parsers for git output. All functions are static and side-effect free.
public enum GitParser {
    /// Counts entries in `git status --porcelain=v1` output.
    public static func countStatusEntries(_ output: String) -> Int {
        output.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    /// Parses `git worktree list --porcelain` into blocks. The first block is
    /// the main working tree (`isMain == true`).
    public static func parseWorktreeBlocks(_ output: String) -> [(path: String, isMain: Bool)] {
        var blocks: [(path: String, isMain: Bool)] = []
        var currentPath: String?

        func flush() {
            if let path = currentPath {
                blocks.append((path, blocks.isEmpty))
            }
            currentPath = nil
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(line)
            if line.hasPrefix("worktree ") {
                flush()
                currentPath = String(line.dropFirst("worktree ".count))
            }
            // HEAD/branch/bare/detached lines carry no path; ignored here.
        }
        flush()
        return blocks
    }

    /// Parses `git log -1 --format=%ct` into a Date.
    public static func parseCommitTimestamp(_ output: String) -> Date? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let epoch = TimeInterval(trimmed) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
}
