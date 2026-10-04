import Foundation

public struct InstallerPaths: Sendable {
    public let home: URL
    public let supportRoot: URL
    public let resources: URL
    public let product: InstallerProductDefinition

    public init(home: URL, supportRoot: URL, resources: URL, product: InstallerProductDefinition = .prototypeFixture) {
        self.home = home.standardizedFileURL
        self.supportRoot = supportRoot.standardizedFileURL
        self.resources = resources.standardizedFileURL
        self.product = product
    }

    public static func live(resources: URL) throws -> InstallerPaths {
        let environment = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: environment["CODEX_PET_INSTALLER_PROTOTYPE_HOME"] ?? NSHomeDirectory(), isDirectory: true)
        let product = try InstallerProductDefinition.load(resources: resources)
        let root = environment["CODEX_PET_INSTALLER_PROTOTYPE_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent("Library/Application Support/\(product.supportDirectoryName)", isDirectory: true)
        return InstallerPaths(home: home, supportRoot: root, resources: resources, product: product)
    }

    public var runtimeRoot: URL { supportRoot.appendingPathComponent("runtime", isDirectory: true) }
    public var runtimeApp: URL { runtimeRoot.appendingPathComponent(product.runtimeAppName, isDirectory: true) }
    public var stagingRoot: URL { supportRoot.appendingPathComponent("staging", isDirectory: true) }
    public var backupsRoot: URL { supportRoot.appendingPathComponent("backups", isDirectory: true) }
    public var rollbackRoot: URL { supportRoot.appendingPathComponent("rollback", isDirectory: true) }
    public var logsRoot: URL { supportRoot.appendingPathComponent("logs", isDirectory: true) }
    public var metadataRoot: URL { supportRoot.appendingPathComponent("metadata", isDirectory: true) }
    public var locksRoot: URL { supportRoot.appendingPathComponent("locks", isDirectory: true) }
    public var operationLock: URL { locksRoot.appendingPathComponent("operation.lock", isDirectory: true) }
    public var metadataFile: URL { metadataRoot.appendingPathComponent("installed.json") }
    public var transactionFile: URL { metadataRoot.appendingPathComponent("active-transaction.json") }
    public var logFile: URL { logsRoot.appendingPathComponent("installer.log") }
    public var codexHome: URL { home.appendingPathComponent(".codex", isDirectory: true) }
    public var codexConfig: URL { codexHome.appendingPathComponent("config.toml") }
    public var codexGlobalState: URL { codexHome.appendingPathComponent(".codex-global-state.json") }
    public var petsRoot: URL { codexHome.appendingPathComponent("pets", isDirectory: true) }
    public var targetPet: URL { petsRoot.appendingPathComponent(product.petID, isDirectory: true) }
    public var protectedDailyLauncher: URL { home.appendingPathComponent("Applications/Codex Pet Toolkit.app", isDirectory: true) }
    public var protectedDailySupport: URL { home.appendingPathComponent("Library/Application Support/Codex Pet Toolkit", isDirectory: true) }
    public var bundledToolkit: URL { resources.appendingPathComponent("toolkit", isDirectory: true) }
    public var bundledNode: URL { resources.appendingPathComponent("runtime/node") }
    public var payloadRoot: URL { resources.appendingPathComponent("payload", isDirectory: true) }
    public var payloadPet: URL { payloadRoot.appendingPathComponent("pet/\(product.petID)", isDirectory: true) }
    public var pinRecord: URL { resources.appendingPathComponent("metadata/pin.json") }
    public var nodeProvenanceManifest: URL { resources.appendingPathComponent("metadata/node-provenance.json") }
    public var thirdPartyNotices: URL { resources.appendingPathComponent("THIRD-PARTY-NOTICES.txt") }
    public var toolkitFileManifest: URL { resources.appendingPathComponent("metadata/toolkit-files.sha256") }
    public var toolkitConfig: URL { bundledToolkit.appendingPathComponent("config/\(product.toolkitConfigFilename)") }

    public static let officialCandidates = [
        URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
    ]
}
