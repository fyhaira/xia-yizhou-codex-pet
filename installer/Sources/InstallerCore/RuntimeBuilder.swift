import Foundation

public struct RuntimeBuildResult: Sendable {
    public let stagedApp: URL
    public let asarSHA256: String?
    public init(stagedApp: URL, asarSHA256: String?) { self.stagedApp = stagedApp; self.asarSHA256 = asarSHA256 }
}

public protocol RuntimeBuilding: Sendable {
    func build(sourceApp: URL, manifest: CompatibilityManifest, manifestURL: URL, aliases: [VerifiedPetIdentityAlias], paths: InstallerPaths, workspace: URL, logger: InstallerLogger) throws -> RuntimeBuildResult
    func verify(app: URL, paths: InstallerPaths, workspace: URL, logger: InstallerLogger) throws
}

public struct BundledToolkitRuntimeBuilder: RuntimeBuilding {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func build(sourceApp: URL, manifest: CompatibilityManifest, manifestURL: URL, aliases: [VerifiedPetIdentityAlias], paths: InstallerPaths, workspace: URL, logger: InstallerLogger) throws -> RuntimeBuildResult {
        let fm = FileManager.default
        let engine = workspace.appendingPathComponent("engine", isDirectory: true)
        try fm.copyItem(at: paths.bundledToolkit, to: engine)
        let output = engine.appendingPathComponent("local/apps/\(paths.product.runtimeAppName)", isDirectory: true)
        let config = engine.appendingPathComponent("config/\(paths.product.toolkitConfigFilename)")
        try addVerifiedCapabilityAliases(aliases, to: config, expectedStablePetID: paths.product.petID)
        let copiedManifest = engine.appendingPathComponent("compatibility/\(manifest.codexVersion)-build-\(manifest.buildNumber).json")
        logger.write("runtime-build", "Applying pinned toolkit \(manifest.id)")
        let result = try runner.run(paths.bundledNode, [
            engine.appendingPathComponent("src/cli/build.mjs").path,
            "--source", sourceApp.path,
            "--config", config.path,
            "--manifest", copiedManifest.path,
            "--output", output.path,
        ], environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": paths.home.path])
        guard result.exitCode == 0 else {
            logger.write("runtime-build-failed", "exit=\(result.exitCode) stderr=\(result.stderr.suffix(8192)) stdout=\(result.stdout.suffix(8192))")
            throw InstallerError.message("Managed runtime build failed (exit \(result.exitCode))")
        }
        let asar = output.appendingPathComponent("Contents/Resources/app.asar")
        return RuntimeBuildResult(stagedApp: output, asarSHA256: try? Hashing.sha256(asar))
    }

    private func addVerifiedCapabilityAliases(_ aliases: [VerifiedPetIdentityAlias], to configURL: URL, expectedStablePetID: String) throws {
        guard !aliases.isEmpty else { return }
        let encoded = try Self.configurationDataAddingVerifiedAliases(aliases, to: Data(contentsOf: configURL), expectedStablePetID: expectedStablePetID)
        try encoded.write(to: configURL, options: .atomic)
    }

    public static func configurationDataAddingVerifiedAliases(_ aliases: [VerifiedPetIdentityAlias], to data: Data, expectedStablePetID: String = prototypePetID) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var capabilities = root["petCapabilities"] as? [String: Any] else {
            throw InstallerError.message("Prototype capability configuration is invalid")
        }
        var usedEffectiveIDs = Set<String>()
        for alias in aliases {
            guard alias.verificationVersion == 1,
                  alias.stableLocalPetID == expectedStablePetID,
                  alias.effectiveRuntimePetID.hasPrefix("pet_"),
                  usedEffectiveIDs.insert(alias.effectiveRuntimePetID).inserted,
                  capabilities[alias.effectiveRuntimePetID] == nil,
                  let stableCapability = capabilities[alias.stableLocalPetID] else {
                throw InstallerError.message("Verified capability alias is invalid or ambiguous")
            }
            capabilities[alias.effectiveRuntimePetID] = stableCapability
        }
        root["petCapabilities"] = capabilities
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public func verify(app: URL, paths: InstallerPaths, workspace: URL, logger: InstallerLogger) throws {
        let engine = workspace.appendingPathComponent("engine", isDirectory: true)
        let result = try runner.run(paths.bundledNode, [engine.appendingPathComponent("src/cli/verify.mjs").path, app.path], environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": paths.home.path])
        guard result.exitCode == 0 else {
            logger.write("runtime-verify-failed", "exit=\(result.exitCode) stderr=\(result.stderr.suffix(8192)) stdout=\(result.stdout.suffix(8192))")
            throw InstallerError.message("Managed runtime verification failed (exit \(result.exitCode))")
        }
    }
}
