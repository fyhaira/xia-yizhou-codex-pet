import Foundation

public struct CompatibilityInspector {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func architecture() -> String {
        var system = utsname(); uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    public func locateOfficial(candidates: [URL] = InstallerPaths.officialCandidates) -> URL? {
        candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }
    }

    public func appFacts(_ app: URL) throws -> (version: String, build: String) {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: plist) as? [String: Any],
              let version = dictionary["CFBundleShortVersionString"] as? String,
              let build = dictionary["CFBundleVersion"] as? String else {
            throw InstallerError.message("Could not read Codex version/build from \(app.path)")
        }
        return (version, build)
    }

    public func loadManifest(resources: URL, version: String, build: String) throws -> CompatibilityManifest? {
        let url = resources.appendingPathComponent("toolkit/compatibility/\(version)-build-\(build).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(contentsOf: url))
        guard manifest.codexVersion == version, manifest.buildNumber == build,
              manifest.platform == "darwin", manifest.architecture == "arm64",
              supportedBuildNumbers.contains(build) else { return nil }
        return manifest
    }
}
