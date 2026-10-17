import Foundation
import DevControlCore

/// Records every external invocation so tests can assert that repository
/// paths and other values are passed as discrete argv entries, never
/// concatenated into a shell command string (S8/S12).
final class RecordingRunner: ProcessRunning {
    struct Call {
        let command: String
        let arguments: [String]
        let directory: String?
    }

    private(set) var calls: [Call] = []
    private let respond: ((String, [String]) -> Result<String, Error>)?

    init(respond: ((String, [String]) -> Result<String, Error>)? = nil) {
        self.respond = respond
    }

    func run(_ launchPath: String, _ arguments: [String], in directory: String?) throws -> String {
        calls.append(Call(command: launchPath, arguments: arguments, directory: directory))
        guard let respond else {
            throw ScannerError.commandFailed(launchPath, 1, "no canned output")
        }
        switch respond(launchPath, arguments) {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }
}

func processRunnerTests() {
    // MARK: - Arguments are passed without a shell

    do {
        let runner = ProcessRunner(timeout: 5)
        let output = try runner.run("/bin/echo", ["hello world"], in: nil)
        checkEqual(output.trimmingCharacters(in: .newlines), "hello world",
                   "an argument containing a space stays one argv entry")
    } catch {
        check(false, "echo with a spaced argument threw: \(error)")
    }

    do {
        let runner = ProcessRunner(timeout: 5)
        let output = try runner.run("/bin/echo", ["$(whoami) && rm -rf /"], in: nil)
        checkEqual(output.trimmingCharacters(in: .newlines), "$(whoami) && rm -rf /",
                   "shell metacharacters are passed literally, never interpreted")
    } catch {
        check(false, "echo with shell metacharacters threw: \(error)")
    }

    do {
        let runner = ProcessRunner(timeout: 5)
        let output = try runner.run("/usr/bin/printf", ["%s|%s", "a b", "$(id)"], in: nil)
        checkEqual(output, "a b|$(id)", "separate argv entries survive word splitting")
    } catch {
        check(false, "printf with separate arguments threw: \(error)")
    }

    do {
        let runner = ProcessRunner(timeout: 5)
        let output = try runner.run("/bin/pwd", [], in: "/tmp")
        check(!output.isEmpty, "the working directory argument is honored")
    } catch {
        check(false, "pwd with a working directory threw: \(error)")
    }

    // MARK: - External calls are bounded

    do {
        let runner = ProcessRunner(timeout: 0.5)
        let started = Date()
        var timedOut = false
        do {
            _ = try runner.run("/bin/sleep", ["10"], in: nil)
        } catch let error as ScannerError {
            if case .timedOut = error { timedOut = true }
        } catch {
            check(false, "sleep timeout threw an unexpected error: \(error)")
        }
        let elapsed = Date().timeIntervalSince(started)
        check(timedOut, "a hung command reports a timeout instead of blocking the scan")
        check(elapsed < 5, "a hung command is killed within the timeout bound")
    }

    do {
        let runner = ProcessRunner(timeout: 5)
        var failed = false
        do {
            _ = try runner.run("/bin/sh", ["-c", "exit 3"], in: nil)
        } catch let error as ScannerError {
            if case let .commandFailed(_, status, _) = error { failed = status == 3 }
        } catch {
            check(false, "exit-code failure threw an unexpected error: \(error)")
        }
        check(failed, "a non-zero exit still surfaces its status")
    }

    // MARK: - Process exit, not pipe closure, controls the deadline

    do {
        let runner = ProcessRunner(timeout: 0.1)
        let started = Date()
        var timedOut = false
        do {
            // The child closes both inherited pipes before continuing to run.
            // Pipe EOF must not disable the process timeout.
            _ = try runner.run("/bin/sh", ["-c", "exec 1>&- 2>&-; exec /bin/sleep 1"], in: nil)
        } catch let error as ScannerError {
            if case .timedOut = error { timedOut = true }
        } catch {
            check(false, "closed-stream timeout threw an unexpected error: \(error)")
        }
        check(timedOut, "a process that closes its pipes still observes the timeout")
        check(Date().timeIntervalSince(started) < 3,
              "a closed-stream process is terminated within the timeout bound")
    }

    // MARK: - Scanner invocations keep repository paths in argv

    do {
        let path = "/repos/with spaces/demo"
        let recording = RecordingRunner { command, arguments in
            guard command == "/usr/bin/git" else {
                return .failure(ScannerError.commandFailed(command, 1, "unexpected command"))
            }
            if arguments.contains("worktree") {
                return .success("worktree \(path)\nHEAD abc\nbranch refs/heads/main\n")
            }
            if arguments.contains("symbolic-ref") { return .success("main\n") }
            if arguments.contains("rev-list") { return .success("0\n") }
            return .success("")
        }
        let scanner = GitScanner(gitPath: "/usr/bin/git", runner: recording,
                                 pathExists: { _ in true })
        let status = scanner.scan(repoPath: path, now: date(2026, 10, 16), calendar: cal)
        checkEqual(status.error, nil, "git scan with a spaced repository path succeeds")
        let gitCalls = recording.calls.filter { $0.command == "/usr/bin/git" }
        check(!gitCalls.isEmpty, "git scanner issues external calls")
        check(gitCalls.allSatisfy { Array($0.arguments.prefix(2)) == ["-C", path] },
              "the repository path is a discrete -C argument, not a shell string")
        check(gitCalls.allSatisfy { $0.directory == nil },
              "the repository path is never smuggled in as the process working directory")
    }

    do {
        let recording = RecordingRunner { command, arguments in
            if command == "/usr/bin/git" { return .success("git@github.com:acme/demo.git\n") }
            if command == "/opt/homebrew/bin/gh" {
                return arguments.contains("acme/demo")
                    ? .success("[]")
                    : .failure(ScannerError.commandFailed(command, 1, "slug missing"))
            }
            return .failure(ScannerError.commandFailed(command, 1, "unexpected command"))
        }
        let scanner = GhScanner(ghPath: "/opt/homebrew/bin/gh", gitPath: "/usr/bin/git",
                                runner: recording, pathExists: { _ in true })
        let status = scanner.scan(repoPath: "/repos/demo", slugOverride: nil,
                                  now: date(2026, 10, 16), calendar: cal)
        check(status.available, "gh receives the resolved slug as its own argument")
    }
}
