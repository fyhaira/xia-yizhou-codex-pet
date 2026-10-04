import Foundation

public struct PrototypeTransactionRecord: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let operation: String
    public let runtimeSnapshotPath: String?

    public init(formatVersion: Int = 1, operation: String, runtimeSnapshotPath: String?) {
        self.formatVersion = formatVersion
        self.operation = operation
        self.runtimeSnapshotPath = runtimeSnapshotPath
    }
}

public struct PrototypeRollbackStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func transactionSnapshotURL(in rollbackRoot: URL) -> URL {
        rollbackRoot.appendingPathComponent("transaction-runtime-\(UUID().uuidString).app", isDirectory: true)
    }

    public func moveRuntimeToSnapshot(runtime: URL, snapshot: URL, rollbackRoot: URL) throws {
        try validateOwnedArtifact(snapshot, rollbackRoot: rollbackRoot, allowHistorical: false)
        guard runtime.standardizedFileURL.path != rollbackRoot.standardizedFileURL.path,
              fileManager.fileExists(atPath: runtime.path) else {
            throw InstallerError.message("Prototype runtime is unavailable for transactional snapshot")
        }
        try fileManager.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
        try fileManager.moveItem(at: runtime, to: snapshot)
    }

    public func restoreSnapshot(_ snapshot: URL, to runtime: URL, rollbackRoot: URL) throws {
        try validateOwnedArtifact(snapshot, rollbackRoot: rollbackRoot, allowHistorical: false)
        guard !fileManager.fileExists(atPath: runtime.path) else {
            throw InstallerError.message("Refusing to restore a prototype runtime over an existing destination")
        }
        try fileManager.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: snapshot, to: runtime)
    }

    public func removeSnapshot(_ snapshot: URL, rollbackRoot: URL) throws {
        try validateOwnedArtifact(snapshot, rollbackRoot: rollbackRoot, allowHistorical: true)
        if fileManager.fileExists(atPath: snapshot.path) { try fileManager.removeItem(at: snapshot) }
    }

    @discardableResult
    public func removeStaleHistoricalSnapshots(rollbackRoot: URL, referencedPaths: Set<String>) throws -> [URL] {
        guard fileManager.fileExists(atPath: rollbackRoot.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: rollbackRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var removable: [URL] = []
        for child in children {
            guard isOwnedArtifactName(child.lastPathComponent, allowHistorical: true) else { continue }
            try validateOwnedArtifact(child, rollbackRoot: rollbackRoot, allowHistorical: true)
            if referencedPaths.contains(child.standardizedFileURL.path) { continue }
            removable.append(child)
        }
        for child in removable { try fileManager.removeItem(at: child) }
        return removable
    }

    public func referencedPaths(from transactionFile: URL) throws -> Set<String> {
        guard fileManager.fileExists(atPath: transactionFile.path) else { return [] }
        let record = try JSONDecoder().decode(PrototypeTransactionRecord.self, from: Data(contentsOf: transactionFile))
        return Set([record.runtimeSnapshotPath].compactMap { $0 }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    public func validateOwnedArtifact(_ artifact: URL, rollbackRoot: URL, allowHistorical: Bool) throws {
        let root = rollbackRoot.standardizedFileURL
        let candidate = artifact.standardizedFileURL
        guard candidate.deletingLastPathComponent().path == root.path,
              isOwnedArtifactName(candidate.lastPathComponent, allowHistorical: allowHistorical) else {
            throw InstallerError.message("Refusing rollback cleanup outside the prototype-owned runtime namespace")
        }
        if let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            throw InstallerError.message("Refusing rollback cleanup through a symbolic-link artifact")
        }
        guard candidate.resolvingSymlinksInPath().deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else {
            throw InstallerError.message("Refusing rollback cleanup through a path escape")
        }
    }

    private func isOwnedArtifactName(_ name: String, allowHistorical: Bool) -> Bool {
        let transaction = name.range(of: #"^transaction-runtime-[0-9A-Fa-f-]+\.app$"#, options: .regularExpression) != nil
        if transaction { return true }
        guard allowHistorical else { return false }
        return name.range(of: #"^uninstalled-runtime-[0-9A-Fa-f-]+\.app$"#, options: .regularExpression) != nil
            || name.range(of: #"^(runtime|runtime-alias)-[0-9]+-[0-9A-Fa-f-]+\.app$"#, options: .regularExpression) != nil
    }
}

public enum CodexGlobalStateEditor {
    public static func removingOwnedFirstAwakeMarker(from data: Data, ownedID: String) throws -> Data? {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.message("Codex global state root is malformed; leaving it untouched")
        }
        guard var persisted = root["electron-persisted-atom-state"] as? [String: Any] else { return nil }
        guard let raw = persisted["first-awake-pet-notification-avatar-ids"] else { return nil }
        guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
            throw InstallerError.message("First-awake pet notification state has an unsupported schema; leaving it untouched")
        }
        let strings = values.compactMap { $0 as? String }
        let filtered = strings.filter { $0 != ownedID }
        guard filtered != strings else { return nil }
        persisted["first-awake-pet-notification-avatar-ids"] = filtered
        root["electron-persisted-atom-state"] = persisted
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
