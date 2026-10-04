import Foundation

public final class OperationLock: @unchecked Sendable {
    private let url: URL
    private var held = false
    public init(url: URL) { self.url = url }

    public func acquire() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { throw InstallerError.message("Another installer operation is already active") }
        held = true
        let metadata = "pid=\(getpid())\nstarted=\(ISO8601DateFormatter().string(from: Date()))\n"
        try? metadata.write(to: url.appendingPathComponent("owner.txt"), atomically: true, encoding: .utf8)
    }

    public func release() {
        guard held else { return }
        try? FileManager.default.removeItem(at: url)
        held = false
    }

    deinit { release() }
}
