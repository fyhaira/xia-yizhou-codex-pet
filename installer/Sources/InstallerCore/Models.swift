import Foundation

public let prototypePetID = "codex-pet-installer-prototype-fixture"
public let supportedBuildNumbers: Set<String> = ["8881", "9922", "10789", "11431"]

public struct InstallerProductDefinition: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let minimumInstallerSchemaVersion: Int
    public let payloadVersion: String
    public let petID: String
    public let capabilityKey: String
    public let displayNameEnglish: String
    public let displayNameChinese: String
    public let spritesheetFilename: String
    public let toolkitConfigFilename: String
    public let supportDirectoryName: String
    public let runtimeAppName: String
    public let productionSleepMS: Int

    public static let prototypeFixture = InstallerProductDefinition(
        schemaVersion: 1,
        minimumInstallerSchemaVersion: 3,
        payloadVersion: "fixture-v1",
        petID: prototypePetID,
        capabilityKey: prototypePetID,
        displayNameEnglish: "Codex Pet Installer Prototype",
        displayNameChinese: "Codex 桌宠安装器原型",
        spritesheetFilename: "spritesheet.png",
        toolkitConfigFilename: "prototype.qa.json",
        supportDirectoryName: "Codex Pet Installer Prototype",
        runtimeAppName: "Codex Pet Installer Prototype Runtime.app",
        productionSleepMS: 8000
    )

    public func validate() throws {
        guard schemaVersion == 1,
              minimumInstallerSchemaVersion <= 3,
              petID.range(of: #"^[a-z0-9][a-z0-9-]+$"#, options: .regularExpression) != nil,
              capabilityKey == petID,
              ["spritesheet.png", "spritesheet.webp"].contains(spritesheetFilename),
              toolkitConfigFilename.range(of: #"^[A-Za-z0-9._-]+\.json$"#, options: .regularExpression) != nil,
              !supportDirectoryName.contains("/"), !runtimeAppName.contains("/"), runtimeAppName.hasSuffix(".app"),
              [8000, 180000].contains(productionSleepMS) else {
            throw InstallerError.message("Installer product definition is unsupported or malformed")
        }
    }

    public static func load(resources: URL) throws -> InstallerProductDefinition {
        let url = resources.appendingPathComponent("metadata/product.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .prototypeFixture }
        let product = try JSONDecoder().decode(InstallerProductDefinition.self, from: Data(contentsOf: url))
        try product.validate()
        return product
    }
}

public enum PetPayloadOwnership: String, Codable, Sendable {
    case installerOwned
    case preservedPreExistingIdentical
}

public struct CompatibilityManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let id: String
    public let platform: String
    public let architecture: String
    public let codexVersion: String
    public let buildNumber: String
    public let transformProfile: String
    public init(formatVersion: Int, id: String, platform: String, architecture: String, codexVersion: String, buildNumber: String, transformProfile: String) {
        self.formatVersion = formatVersion; self.id = id; self.platform = platform; self.architecture = architecture
        self.codexVersion = codexVersion; self.buildNumber = buildNumber; self.transformProfile = transformProfile
    }
}

public struct PinRecord: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let toolkitCommit: String
    public let toolkitGitTree: String
    public let toolkitTreeSHA256: String
    public let toolkitFileManifestSHA256: String
    public let asarPackageVersion: String
    public let asarPackageIntegrity: String
    public let bundledNodeVersion: String
    public let bundledNodeUpstreamSHA256: String
    public let bundledNodeSHA256: String
    public let nodeProvenanceManifestSHA256: String
    public let thirdPartyNoticesSHA256: String
    public let supportedBuilds: [String]
    public let payloadFiles: [String: String]
    public init(formatVersion: Int, toolkitCommit: String, toolkitGitTree: String, toolkitTreeSHA256: String, toolkitFileManifestSHA256: String, asarPackageVersion: String, asarPackageIntegrity: String, bundledNodeVersion: String, bundledNodeUpstreamSHA256: String, bundledNodeSHA256: String, nodeProvenanceManifestSHA256: String, thirdPartyNoticesSHA256: String, supportedBuilds: [String], payloadFiles: [String: String]) {
        self.formatVersion = formatVersion; self.toolkitCommit = toolkitCommit; self.toolkitGitTree = toolkitGitTree; self.toolkitTreeSHA256 = toolkitTreeSHA256
        self.toolkitFileManifestSHA256 = toolkitFileManifestSHA256; self.asarPackageVersion = asarPackageVersion; self.asarPackageIntegrity = asarPackageIntegrity
        self.bundledNodeVersion = bundledNodeVersion; self.bundledNodeUpstreamSHA256 = bundledNodeUpstreamSHA256; self.bundledNodeSHA256 = bundledNodeSHA256
        self.nodeProvenanceManifestSHA256 = nodeProvenanceManifestSHA256; self.thirdPartyNoticesSHA256 = thirdPartyNoticesSHA256
        self.supportedBuilds = supportedBuilds; self.payloadFiles = payloadFiles
    }
}

public struct InstalledMetadata: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let installedAt: String
    public let sourceApp: String
    public let sourceVersion: String
    public let sourceBuild: String
    public let manifestID: String
    public let toolkitCommit: String
    public let runtimePath: String
    public let runtimeASARSHA256: String?
    public let petID: String
    public let petFiles: [String: String]
    public let previousSelectedAvatarID: String?
    public let previousEffectiveSelectedAvatarID: String?
    public let verifiedIdentityAliases: [VerifiedPetIdentityAlias]?
    public let displacedPetBackup: String?
    public let configBackup: String?
    public let sleepTimeoutMS: Int
    public let payloadVersion: String?
    public let petOwnership: PetPayloadOwnership?

    public init(formatVersion: Int, installedAt: String, sourceApp: String, sourceVersion: String, sourceBuild: String, manifestID: String, toolkitCommit: String, runtimePath: String, runtimeASARSHA256: String?, petID: String, petFiles: [String: String], previousSelectedAvatarID: String?, previousEffectiveSelectedAvatarID: String?, verifiedIdentityAliases: [VerifiedPetIdentityAlias]?, displacedPetBackup: String?, configBackup: String?, sleepTimeoutMS: Int, payloadVersion: String? = nil, petOwnership: PetPayloadOwnership? = nil) {
        self.formatVersion = formatVersion; self.installedAt = installedAt; self.sourceApp = sourceApp
        self.sourceVersion = sourceVersion; self.sourceBuild = sourceBuild; self.manifestID = manifestID
        self.toolkitCommit = toolkitCommit; self.runtimePath = runtimePath; self.runtimeASARSHA256 = runtimeASARSHA256
        self.petID = petID; self.petFiles = petFiles; self.previousSelectedAvatarID = previousSelectedAvatarID
        self.previousEffectiveSelectedAvatarID = previousEffectiveSelectedAvatarID; self.verifiedIdentityAliases = verifiedIdentityAliases
        self.displacedPetBackup = displacedPetBackup; self.configBackup = configBackup; self.sleepTimeoutMS = sleepTimeoutMS
        self.payloadVersion = payloadVersion; self.petOwnership = petOwnership
    }
}

public struct VerifiedPetIdentityAlias: Codable, Equatable, Sendable {
    public let verificationVersion: Int
    public let stableLocalPetID: String
    public let effectiveRuntimePetID: String
    public let spritesheetFingerprint: String

    public init(verificationVersion: Int = 1, stableLocalPetID: String, effectiveRuntimePetID: String, spritesheetFingerprint: String) {
        self.verificationVersion = verificationVersion
        self.stableLocalPetID = stableLocalPetID
        self.effectiveRuntimePetID = effectiveRuntimePetID
        self.spritesheetFingerprint = spritesheetFingerprint
    }
}

public enum CompatibilityState: String, Codable, Sendable {
    case supported
    case unsupported
    case missingOfficialApp
    case wrongArchitecture
}

public struct ProcessBlocker: Codable, Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let reason: String
}

public struct PreflightReport: Codable, Equatable, Sendable {
    public let state: CompatibilityState
    public let officialAppPath: String?
    public let version: String?
    public let build: String?
    public let architecture: String
    public let manifestID: String?
    public let blockers: [ProcessBlocker]
    public let prototypeInstalled: Bool
    public let dailyUseToolkitPresent: Bool
    public let plannedChanges: [String]
}

public struct VerificationReport: Codable, Equatable, Sendable {
    public let installed: Bool
    public let petValid: Bool
    public let runtimePresent: Bool
    public let configSelected: Bool
    public let metadataValid: Bool
    public let effectiveSelectedAvatarID: String?
    public let verifiedCapabilityAlias: Bool
    public let messages: [String]
}

public enum InstallerError: LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
