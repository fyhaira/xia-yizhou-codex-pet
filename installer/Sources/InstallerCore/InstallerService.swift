import Foundation

public final class InstallerService: @unchecked Sendable {
    public let paths: InstallerPaths
    private let inspector: CompatibilityInspector
    private let processGuard: ProcessGuard
    private let payloadVerifier: PayloadVerifier
    private let identityResolver: PetIdentityAssociationResolver
    private let rollbackStore: PrototypeRollbackStore
    private let runtimeBuilder: any RuntimeBuilding
    private let fileManager: FileManager
    private let logger: InstallerLogger
    private let officialCandidates: [URL]

    public init(
        paths: InstallerPaths,
        inspector: CompatibilityInspector = CompatibilityInspector(),
        processGuard: ProcessGuard = ProcessGuard(),
        payloadVerifier: PayloadVerifier = PayloadVerifier(),
        identityResolver: PetIdentityAssociationResolver = PetIdentityAssociationResolver(),
        runtimeBuilder: any RuntimeBuilding = BundledToolkitRuntimeBuilder(),
        fileManager: FileManager = .default,
        officialCandidates: [URL] = InstallerPaths.officialCandidates
    ) {
        self.paths = paths; self.inspector = inspector; self.processGuard = processGuard
        self.payloadVerifier = payloadVerifier; self.runtimeBuilder = runtimeBuilder
        self.identityResolver = identityResolver
        self.rollbackStore = PrototypeRollbackStore(fileManager: fileManager)
        self.fileManager = fileManager; self.officialCandidates = officialCandidates
        self.logger = InstallerLogger(url: paths.logFile)
    }

    public func preflight() throws -> PreflightReport {
        let petID = paths.product.petID
        let architecture = inspector.architecture()
        let blockers = try processGuard.blockers(paths: paths)
        let installed = fileManager.fileExists(atPath: paths.metadataFile.path)
        let daily = fileManager.fileExists(atPath: paths.protectedDailyLauncher.path) || fileManager.fileExists(atPath: paths.protectedDailySupport.path)
        let plans = [
            "Verify the bundled \(paths.product.displayNameEnglish) payload and pinned enhancer engine",
            "Install only pet id \(petID)",
            "Build a managed copied Codex runtime under this product's private namespace",
            "Set and verify the intended and effective [desktop] pet selection transactionally",
            "Leave the official app and daily-use Toolkit untouched",
        ]
        guard let official = inspector.locateOfficial(candidates: officialCandidates) else {
            return PreflightReport(state: .missingOfficialApp, officialAppPath: nil, version: nil, build: nil, architecture: architecture, manifestID: nil, blockers: blockers, prototypeInstalled: installed, dailyUseToolkitPresent: daily, plannedChanges: plans)
        }
        let facts = try inspector.appFacts(official)
        if architecture != "arm64" {
            return PreflightReport(state: .wrongArchitecture, officialAppPath: official.path, version: facts.version, build: facts.build, architecture: architecture, manifestID: nil, blockers: blockers, prototypeInstalled: installed, dailyUseToolkitPresent: daily, plannedChanges: plans)
        }
        let manifest = try inspector.loadManifest(resources: paths.resources, version: facts.version, build: facts.build)
        return PreflightReport(state: manifest == nil ? .unsupported : .supported, officialAppPath: official.path, version: facts.version, build: facts.build, architecture: architecture, manifestID: manifest?.id, blockers: blockers, prototypeInstalled: installed, dailyUseToolkitPresent: daily, plannedChanges: plans)
    }

    public func dryRun() throws -> PreflightReport {
        let report = try preflight()
        _ = try payloadVerifier.verify(paths: paths)
        return report
    }

    public func verify() throws -> VerificationReport {
        let petID = paths.product.petID
        guard fileManager.fileExists(atPath: paths.metadataFile.path) else {
            return VerificationReport(installed: false, petValid: false, runtimePresent: false, configSelected: false, metadataValid: false, effectiveSelectedAvatarID: nil, verifiedCapabilityAlias: false, messages: ["This installer product is not installed"])
        }
        let metadata = try JSONDecoder().decode(InstalledMetadata.self, from: Data(contentsOf: paths.metadataFile))
        let pin = try payloadVerifier.loadPin(paths: paths)
        let petValid = try payloadVerifier.verifyPet(at: paths.targetPet, expected: pin.payloadFiles, petID: petID)
        let runtimePresent = fileManager.fileExists(atPath: paths.runtimeApp.appendingPathComponent("Contents/Info.plist").path)
        let config = (try? String(contentsOf: paths.codexConfig, encoding: .utf8)) ?? ""
        let intended = try? CodexConfigEditor.selectedAvatar(in: config)
        let effective = try? CodexConfigEditor.effectiveSelectedAvatar(in: config)
        let aliases = metadata.verifiedIdentityAliases ?? []
        var aliasVerified = false
        if let effective, effective.hasPrefix("pet_"), let recorded = aliases.first(where: { $0.effectiveRuntimePetID == effective }) {
            if let resolved = try? identityResolver.resolve(stablePetID: petID, effectivePetID: effective, globalStateURL: paths.codexGlobalState) {
                aliasVerified = resolved == recorded
            }
        }
        let stableSelected = effective == "custom:\(petID)" || effective == petID
        let selectedOK = stableSelected || aliasVerified
        let intendedOK = intended == nil || intended == "custom:\(petID)"
        return VerificationReport(installed: true, petValid: petValid, runtimePresent: runtimePresent, configSelected: selectedOK && intendedOK, metadataValid: metadata.petID == petID && metadata.payloadVersion == paths.product.payloadVersion && supportedBuildNumbers.contains(metadata.sourceBuild), effectiveSelectedAvatarID: effective, verifiedCapabilityAlias: aliasVerified, messages: aliasVerified ? ["Effective cloud pet identity is verified against installer-owned migration and fingerprint evidence"] : [])
    }

    @discardableResult
    public func install(launchAfterInstall: Bool = true) throws -> InstalledMetadata {
        let petID = paths.product.petID
        let lock = OperationLock(url: paths.operationLock)
        try lock.acquire(); defer { lock.release() }
        try requireNoPendingTransaction()
        try processGuard.requireClean(paths: paths)
        let report = try preflight()
        guard report.state == .supported, let appPath = report.officialAppPath,
              let version = report.version, let build = report.build else {
            throw InstallerError.message("Installed Codex build is unsupported; no changes were made")
        }
        let official = URL(fileURLWithPath: appPath, isDirectory: true)
        guard let manifest = try inspector.loadManifest(resources: paths.resources, version: version, build: build) else {
            throw InstallerError.message("Exact compatibility manifest is unavailable")
        }
        let pin = try payloadVerifier.verify(paths: paths)
        let existingMetadata = try? JSONDecoder().decode(InstalledMetadata.self, from: Data(contentsOf: paths.metadataFile))
        if let existingMetadata {
            let report = try verify()
            guard existingMetadata.petID == petID, existingMetadata.payloadVersion == paths.product.payloadVersion,
                  report.petValid, report.runtimePresent, report.configSelected, report.metadataValid else {
                throw InstallerError.message("An existing installer state does not match this exact payload version")
            }
            logger.write("install", "identical payload version already installed; no files replaced")
            if launchAfterInstall { try launch() }
            return existingMetadata
        }
        let preExistingIdentical = fileManager.fileExists(atPath: paths.targetPet.path)
        let preExistingPetMatches = preExistingIdentical
            ? try payloadVerifier.verifyPet(at: paths.targetPet, expected: pin.payloadFiles, petID: petID)
            : false
        if preExistingIdentical && !preExistingPetMatches {
            throw InstallerError.message("A different pre-existing pet package uses id \(petID); refusing to overwrite")
        }
        let originalConfig = (try? String(contentsOf: paths.codexConfig, encoding: .utf8)) ?? ""
        let previousSelection = try CodexConfigEditor.selectedAvatar(in: originalConfig)
        let previousEffectiveSelection = try CodexConfigEditor.effectiveSelectedAvatar(in: originalConfig)
        try createOwnedRoots()
        let operation = paths.stagingRoot.appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: operation, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: operation) }
        let stagedPet = operation.appendingPathComponent(petID, isDirectory: true)
        if !preExistingIdentical {
            try fileManager.copyItem(at: paths.payloadPet, to: stagedPet)
            guard try payloadVerifier.verifyPet(at: stagedPet, expected: pin.payloadFiles, petID: petID) else { throw InstallerError.message("Staged pet verification failed") }
        }
        let manifestURL = paths.bundledToolkit.appendingPathComponent("compatibility/\(version)-build-\(build).json")
        let runtime = try runtimeBuilder.build(sourceApp: official, manifest: manifest, manifestURL: manifestURL, aliases: [], paths: paths, workspace: operation, logger: logger)
        try runtimeBuilder.verify(app: runtime.stagedApp, paths: paths, workspace: operation, logger: logger)

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let configBackup = paths.backupsRoot.appendingPathComponent("config-\(timestamp).toml")
        if fileManager.fileExists(atPath: paths.codexConfig.path) { try fileManager.copyItem(at: paths.codexConfig, to: configBackup) }
        let displacedPet: URL? = nil
        var runtimeRollback: URL?
        do {
            runtimeRollback = try fileManager.replaceDirectoryAtomically(staged: runtime.stagedApp, destination: paths.runtimeApp, rollbackRoot: paths.rollbackRoot, label: "runtime")
            if let runtimeRollback { try writeTransaction(operation: "install", runtimeSnapshot: runtimeRollback) }
            if !preExistingIdentical { try fileManager.moveItem(at: stagedPet, to: paths.targetPet) }
            let intendedConfig = try CodexConfigEditor.settingSelectedAvatar("custom:\(petID)", in: originalConfig)
            let updatedConfig = try CodexConfigEditor.settingEffectiveSelectedAvatar("custom:\(petID)", in: intendedConfig)
            try CodexConfigEditor.writeAtomically(updatedConfig, to: paths.codexConfig)
            let metadata = InstalledMetadata(formatVersion: 3, installedAt: ISO8601DateFormatter().string(from: Date()), sourceApp: appPath, sourceVersion: version, sourceBuild: build, manifestID: manifest.id, toolkitCommit: pin.toolkitCommit, runtimePath: paths.runtimeApp.path, runtimeASARSHA256: runtime.asarSHA256, petID: petID, petFiles: pin.payloadFiles, previousSelectedAvatarID: previousSelection, previousEffectiveSelectedAvatarID: previousEffectiveSelection, verifiedIdentityAliases: [], displacedPetBackup: nil, configBackup: fileManager.fileExists(atPath: configBackup.path) ? configBackup.path : nil, sleepTimeoutMS: paths.product.productionSleepMS, payloadVersion: paths.product.payloadVersion, petOwnership: preExistingIdentical ? .preservedPreExistingIdentical : .installerOwned)
            try fileManager.createDirectory(at: paths.metadataRoot, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(metadata).write(to: paths.metadataFile, options: .atomic)
            let verified = try verify()
            guard verified.petValid && verified.runtimePresent && verified.configSelected && verified.metadataValid else { throw InstallerError.message("Post-install verification failed") }
            if let runtimeRollback { try rollbackStore.removeSnapshot(runtimeRollback, rollbackRoot: paths.rollbackRoot) }
            try clearTransaction()
            logger.write("install", "success version=\(version) build=\(build) runtime=prototype-managed")
            if launchAfterInstall { try launch() }
            return metadata
        } catch {
            if !preExistingIdentical { try? fileManager.removeItem(at: paths.targetPet) }
            if let displacedPet, fileManager.fileExists(atPath: displacedPet.path) { try? fileManager.moveItem(at: displacedPet, to: paths.targetPet) }
            if fileManager.fileExists(atPath: configBackup.path) {
                try? fileManager.removeItem(at: paths.codexConfig)
                try? fileManager.copyItem(at: configBackup, to: paths.codexConfig)
            }
            if let runtimeRollback, fileManager.fileExists(atPath: runtimeRollback.path) {
                try? fileManager.removeItem(at: paths.runtimeApp)
                try? fileManager.moveItem(at: runtimeRollback, to: paths.runtimeApp)
            } else { try? fileManager.removeItem(at: paths.runtimeApp) }
            try? clearTransaction()
            logger.write("install-failed", error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    public func reconcileVerifiedIdentityAlias(launchAfterRebuild: Bool = true) throws -> InstalledMetadata {
        let petID = paths.product.petID
        let lock = OperationLock(url: paths.operationLock)
        try lock.acquire(); defer { lock.release() }
        try requireNoPendingTransaction()
        try processGuard.requireClean(paths: paths)
        guard fileManager.fileExists(atPath: paths.metadataFile.path) else { throw InstallerError.message("Prototype is not installed") }
        let oldMetadata = try JSONDecoder().decode(InstalledMetadata.self, from: Data(contentsOf: paths.metadataFile))
        let pin = try payloadVerifier.verify(paths: paths)
        guard try payloadVerifier.verifyPet(at: paths.targetPet, expected: pin.payloadFiles, petID: petID) else { throw InstallerError.message("Installed pet payload verification failed") }
        let config = (try? String(contentsOf: paths.codexConfig, encoding: .utf8)) ?? ""
        guard let effective = try CodexConfigEditor.effectiveSelectedAvatar(in: config) else { throw InstallerError.message("Effective [desktop] pet selection is absent") }
        guard let alias = try identityResolver.resolve(stablePetID: petID, effectivePetID: effective, globalStateURL: paths.codexGlobalState) else {
            throw InstallerError.message("Effective pet remains the stable local identity; no cloud alias is required")
        }
        guard let official = inspector.locateOfficial(candidates: officialCandidates) else { throw InstallerError.message("Official Codex app is missing") }
        let facts = try inspector.appFacts(official)
        guard facts.version == oldMetadata.sourceVersion, facts.build == oldMetadata.sourceBuild,
              let manifest = try inspector.loadManifest(resources: paths.resources, version: facts.version, build: facts.build) else {
            throw InstallerError.message("Exact installed source build no longer matches prototype metadata")
        }
        let operation = paths.stagingRoot.appendingPathComponent("reconcile-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: operation, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: operation) }
        let manifestURL = paths.bundledToolkit.appendingPathComponent("compatibility/\(facts.version)-build-\(facts.build).json")
        let runtime = try runtimeBuilder.build(sourceApp: official, manifest: manifest, manifestURL: manifestURL, aliases: [alias], paths: paths, workspace: operation, logger: logger)
        try runtimeBuilder.verify(app: runtime.stagedApp, paths: paths, workspace: operation, logger: logger)
        let rollback = try fileManager.replaceDirectoryAtomically(staged: runtime.stagedApp, destination: paths.runtimeApp, rollbackRoot: paths.rollbackRoot, label: "runtime-alias")
        if let rollback { try writeTransaction(operation: "identity-reconcile", runtimeSnapshot: rollback) }
        do {
            let metadata = InstalledMetadata(formatVersion: oldMetadata.formatVersion, installedAt: oldMetadata.installedAt, sourceApp: oldMetadata.sourceApp, sourceVersion: oldMetadata.sourceVersion, sourceBuild: oldMetadata.sourceBuild, manifestID: oldMetadata.manifestID, toolkitCommit: oldMetadata.toolkitCommit, runtimePath: oldMetadata.runtimePath, runtimeASARSHA256: runtime.asarSHA256, petID: oldMetadata.petID, petFiles: oldMetadata.petFiles, previousSelectedAvatarID: oldMetadata.previousSelectedAvatarID, previousEffectiveSelectedAvatarID: oldMetadata.previousEffectiveSelectedAvatarID, verifiedIdentityAliases: [alias], displacedPetBackup: oldMetadata.displacedPetBackup, configBackup: oldMetadata.configBackup, sleepTimeoutMS: oldMetadata.sleepTimeoutMS, payloadVersion: oldMetadata.payloadVersion, petOwnership: oldMetadata.petOwnership)
            try JSONEncoder.pretty.encode(metadata).write(to: paths.metadataFile, options: .atomic)
            let verified = try verify()
            guard verified.configSelected && verified.verifiedCapabilityAlias && verified.metadataValid else { throw InstallerError.message("Verified capability alias post-check failed") }
            if let rollback { try rollbackStore.removeSnapshot(rollback, rollbackRoot: paths.rollbackRoot) }
            try clearTransaction()
            logger.write("identity-reconcile", "verified one installer-owned cloud identity alias")
            if launchAfterRebuild { try launch() }
            return metadata
        } catch {
            try? fileManager.removeItem(at: paths.runtimeApp)
            if let rollback, fileManager.fileExists(atPath: rollback.path) { try? fileManager.moveItem(at: rollback, to: paths.runtimeApp) }
            try? clearTransaction()
            throw error
        }
    }

    public func launch() throws {
        try processGuard.requireClean(paths: paths)
        let report = try verify()
        guard report.petValid && report.runtimePresent && report.configSelected && report.metadataValid else { throw InstallerError.message("Prototype verification failed; refusing to launch") }
        let result = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/open"), [paths.runtimeApp.path], environment: nil)
        if result.exitCode != 0 { throw InstallerError.message("Managed runtime launch failed: \(result.stderr)") }
        logger.write("launch", "managed runtime launched with normal shared profile; no isolation flags")
    }

    public func uninstall() throws {
        let petID = paths.product.petID
        let lock = OperationLock(url: paths.operationLock)
        try lock.acquire(); defer { lock.release() }
        try requireNoPendingTransaction()
        try processGuard.requireClean(paths: paths)
        guard fileManager.fileExists(atPath: paths.metadataFile.path) else { throw InstallerError.message("Prototype is not installed") }
        let metadata = try JSONDecoder().decode(InstalledMetadata.self, from: Data(contentsOf: paths.metadataFile))
        let pin = try payloadVerifier.loadPin(paths: paths)
        guard try payloadVerifier.verifyPet(at: paths.targetPet, expected: pin.payloadFiles, petID: petID) else {
            throw InstallerError.message("Installed prototype pet was modified; refusing destructive removal")
        }
        let currentConfig = (try? String(contentsOf: paths.codexConfig, encoding: .utf8)) ?? ""
        let currentSelection = try CodexConfigEditor.selectedAvatar(in: currentConfig)
        let currentEffective = try CodexConfigEditor.effectiveSelectedAvatar(in: currentConfig)
        let ownedEffectiveIDs = Set(["custom:\(petID)", petID] + (metadata.verifiedIdentityAliases ?? []).map(\.effectiveRuntimePetID))
        var restored = currentConfig
        if currentSelection == "custom:\(petID)" {
            restored = try metadata.previousSelectedAvatarID.map { try CodexConfigEditor.settingSelectedAvatar($0, in: restored) } ?? CodexConfigEditor.removingSelectedAvatar(in: restored)
        }
        if let currentEffective, ownedEffectiveIDs.contains(currentEffective) {
            restored = try CodexConfigEditor.restoringEffectiveSelectedAvatar(metadata.previousEffectiveSelectedAvatarID, in: restored)
        }
        let originalConfigData = Data(currentConfig.utf8)
        let originalGlobalState = fileManager.fileExists(atPath: paths.codexGlobalState.path) ? try Data(contentsOf: paths.codexGlobalState) : nil
        let updatedGlobalState = try originalGlobalState.flatMap {
            try CodexGlobalStateEditor.removingOwnedFirstAwakeMarker(from: $0, ownedID: "custom:\(petID)")
        }

        try createOwnedRoots()
        let operation = paths.stagingRoot.appendingPathComponent("uninstall-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: operation, withIntermediateDirectories: true)
        let stagedPet = operation.appendingPathComponent("owned-pet", isDirectory: true)
        let stagedMetadata = operation.appendingPathComponent("installed.json")
        let runtimeSnapshot = fileManager.fileExists(atPath: paths.runtimeApp.path) ? rollbackStore.transactionSnapshotURL(in: paths.rollbackRoot) : nil
        try writeTransaction(operation: "uninstall", runtimeSnapshot: runtimeSnapshot)

        var displacedWasRestored = false
        do {
            if let runtimeSnapshot { try rollbackStore.moveRuntimeToSnapshot(runtime: paths.runtimeApp, snapshot: runtimeSnapshot, rollbackRoot: paths.rollbackRoot) }
            let petOwnership = metadata.petOwnership ?? .installerOwned
            if petOwnership == .installerOwned { try fileManager.moveItem(at: paths.targetPet, to: stagedPet) }
            if let backup = metadata.displacedPetBackup {
                let backupURL = URL(fileURLWithPath: backup, isDirectory: true)
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.moveItem(at: backupURL, to: paths.targetPet)
                    displacedWasRestored = true
                }
            }
            if restored != currentConfig { try CodexConfigEditor.writeAtomically(restored, to: paths.codexConfig) }
            if let updatedGlobalState { try CodexConfigEditor.writeDataAtomically(updatedGlobalState, to: paths.codexGlobalState) }
            try fileManager.moveItem(at: paths.metadataFile, to: stagedMetadata)

            let referenced = try rollbackStore.referencedPaths(from: paths.transactionFile)
            _ = try rollbackStore.removeStaleHistoricalSnapshots(rollbackRoot: paths.rollbackRoot, referencedPaths: referenced)
            if let runtimeSnapshot { try rollbackStore.removeSnapshot(runtimeSnapshot, rollbackRoot: paths.rollbackRoot) }
            try fileManager.removeItem(at: operation)
            try clearTransaction()
            logger.write("uninstall", "prototype-owned runtime, pet, notification marker, and transaction snapshots removed; unrelated Codex data preserved")
        } catch {
            var recovered = true
            if displacedWasRestored, let backup = metadata.displacedPetBackup, fileManager.fileExists(atPath: paths.targetPet.path) {
                do { try fileManager.moveItem(at: paths.targetPet, to: URL(fileURLWithPath: backup, isDirectory: true)) } catch { recovered = false }
            }
            if fileManager.fileExists(atPath: stagedPet.path), !fileManager.fileExists(atPath: paths.targetPet.path) {
                do { try fileManager.moveItem(at: stagedPet, to: paths.targetPet) } catch { recovered = false }
            }
            do { try CodexConfigEditor.writeDataAtomically(originalConfigData, to: paths.codexConfig) } catch { recovered = false }
            if let originalGlobalState, updatedGlobalState != nil {
                do { try CodexConfigEditor.writeDataAtomically(originalGlobalState, to: paths.codexGlobalState) } catch { recovered = false }
            }
            if fileManager.fileExists(atPath: stagedMetadata.path), !fileManager.fileExists(atPath: paths.metadataFile.path) {
                do { try fileManager.moveItem(at: stagedMetadata, to: paths.metadataFile) } catch { recovered = false }
            }
            if let runtimeSnapshot, fileManager.fileExists(atPath: runtimeSnapshot.path), !fileManager.fileExists(atPath: paths.runtimeApp.path) {
                do { try rollbackStore.restoreSnapshot(runtimeSnapshot, to: paths.runtimeApp, rollbackRoot: paths.rollbackRoot) } catch { recovered = false }
            }
            if recovered { try? clearTransaction() }
            logger.write("uninstall-failed", recovered ? "transaction rolled back" : "recovery incomplete; transaction record retained")
            throw error
        }
    }

    public func cleanupHistoricalUninstallResidue() throws {
        let lock = OperationLock(url: paths.operationLock)
        try lock.acquire(); defer { lock.release() }
        try requireNoPendingTransaction()
        try processGuard.requireClean(paths: paths)
        guard !fileManager.fileExists(atPath: paths.metadataFile.path),
              !fileManager.fileExists(atPath: paths.runtimeApp.path),
              !fileManager.fileExists(atPath: paths.targetPet.path) else {
            throw InstallerError.message("Prototype is installed; historical cleanup is only available after uninstall")
        }
        let originalGlobalState = fileManager.fileExists(atPath: paths.codexGlobalState.path) ? try Data(contentsOf: paths.codexGlobalState) : nil
        let updatedGlobalState = try originalGlobalState.flatMap {
            try CodexGlobalStateEditor.removingOwnedFirstAwakeMarker(from: $0, ownedID: "custom:\(paths.product.petID)")
        }
        try createOwnedRoots()
        try writeTransaction(operation: "historical-uninstall-cleanup", runtimeSnapshot: nil)
        do {
            _ = try rollbackStore.removeStaleHistoricalSnapshots(rollbackRoot: paths.rollbackRoot, referencedPaths: [])
            if let updatedGlobalState { try CodexConfigEditor.writeDataAtomically(updatedGlobalState, to: paths.codexGlobalState) }
            try clearTransaction()
            logger.write("uninstall-cleanup", "verified stale prototype runtime archives and exact owned notification marker removed")
        } catch {
            try? clearTransaction()
            throw error
        }
    }

    private func createOwnedRoots() throws {
        for url in [paths.runtimeRoot, paths.stagingRoot, paths.backupsRoot, paths.rollbackRoot, paths.logsRoot, paths.metadataRoot, paths.locksRoot, paths.petsRoot] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func writeTransaction(operation: String, runtimeSnapshot: URL?) throws {
        try fileManager.createDirectory(at: paths.metadataRoot, withIntermediateDirectories: true)
        let record = PrototypeTransactionRecord(operation: operation, runtimeSnapshotPath: runtimeSnapshot?.path)
        try JSONEncoder.pretty.encode(record).write(to: paths.transactionFile, options: .atomic)
    }

    private func clearTransaction() throws {
        if fileManager.fileExists(atPath: paths.transactionFile.path) { try fileManager.removeItem(at: paths.transactionFile) }
    }

    private func requireNoPendingTransaction() throws {
        guard !fileManager.fileExists(atPath: paths.transactionFile.path) else {
            throw InstallerError.message("A prototype transaction requires recovery; refusing to start another operation")
        }
    }
}

extension JSONEncoder {
    public static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
