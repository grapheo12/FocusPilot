import Foundation

public struct GitResult: Sendable {
    public var status: Int32
    public var output: String
}

public enum GitError: LocalizedError {
    case commandFailed(arguments: [String], status: Int32, output: String)
    case unrelatedChanges([String])

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let status, let output):
            "git \(arguments.joined(separator: " ")) failed (\(status)): \(output)"
        case .unrelatedChanges(let paths):
            "Compaction requires a clean repository. Unrelated changes: \(paths.joined(separator: ", "))"
        }
    }
}

public struct GitClient: Sendable {
    public let repositoryURL: URL

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    public func initializeIfNeeded() throws {
        let probe = try run(["rev-parse", "--is-inside-work-tree"], allowFailure: true)
        if probe.status != 0 {
            _ = try run(["init"])
        }
        if try run(["config", "--get", "user.name"], allowFailure: true).status != 0 {
            _ = try run(["config", "user.name", "FocusPilot"])
        }
        if try run(["config", "--get", "user.email"], allowFailure: true).status != 0 {
            _ = try run(["config", "user.email", "focuspilot@localhost"])
        }
    }

    @discardableResult
    public func commitVaultChanges(message: String) throws -> Bool {
        _ = try run(["add", "-A", "--", "vault"])
        let diff = try run(["diff", "--cached", "--quiet"], allowFailure: true)
        if diff.status == 0 { return false }
        _ = try run(["commit", "-m", message])
        return true
    }

    public func ensureNoUnrelatedChanges() throws {
        let result = try run(["status", "--porcelain", "--untracked-files=all"])
        let unrelated = result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                let path = line.count > 3 ? String(line.dropFirst(3)) : line
                return !path.hasPrefix("vault/")
            }
        if !unrelated.isEmpty { throw GitError.unrelatedChanges(unrelated) }
    }

    public func fetch() throws {
        _ = try run(["fetch", "--prune"])
    }

    public func pullRebase() throws {
        _ = try run(["pull", "--rebase", "--autostash"])
    }

    public func push() throws {
        _ = try run(["push"])
    }

    public func hasRemote() throws -> Bool {
        let output = try run(["remote"], allowFailure: true).output
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    public func run(_ arguments: [String], allowFailure: Bool = false) throws -> GitResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let result = GitResult(status: process.terminationStatus, output: output)
        if !allowFailure && result.status != 0 {
            throw GitError.commandFailed(arguments: arguments, status: result.status, output: result.output)
        }
        return result
    }
}
