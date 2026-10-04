import CryptoKit
import Foundation

public enum Hashing {
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public protocol CommandRunning: Sendable {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String]?) throws -> CommandResult
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("codex-pet-installer-command-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outURL = scratch.appendingPathComponent("stdout"), errURL = scratch.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        process.standardOutput = out; process.standardError = err
        do { try process.run(); process.waitUntilExit() }
        catch { try? out.close(); try? err.close(); throw error }
        try out.close(); try err.close()
        let stdout = String(decoding: try Data(contentsOf: outURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
        let captureLimit = 4 * 1024 * 1024
        return CommandResult(exitCode: process.terminationStatus, stdout: String(stdout.suffix(captureLimit)), stderr: String(stderr.suffix(captureLimit)))
    }
}

public final class InstallerLogger: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func write(_ step: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        let clean = message
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            .replacingOccurrences(of: "(?i)(token|password|cookie|authorization)[^\\n]{0,200}", with: "[redacted]", options: .regularExpression)
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(step)] \(clean)\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch { /* Logging must never expose or replace installer state. */ }
    }
}

extension FileManager {
    func replaceDirectoryAtomically(staged: URL, destination: URL, rollbackRoot: URL, label: String) throws -> URL? {
        try createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rollback: URL?
        if fileExists(atPath: destination.path) {
            try createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
            rollback = rollbackRoot.appendingPathComponent("\(label)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).app", isDirectory: true)
            try moveItem(at: destination, to: rollback!)
        }
        do { try moveItem(at: staged, to: destination) }
        catch {
            if let rollback, !fileExists(atPath: destination.path) { try? moveItem(at: rollback, to: destination) }
            throw error
        }
        return rollback
    }
}
