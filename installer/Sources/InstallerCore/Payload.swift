import Foundation

public struct PayloadVerifier: Sendable {
    public init() {}

    public func loadPin(paths: InstallerPaths) throws -> PinRecord {
        try JSONDecoder().decode(PinRecord.self, from: Data(contentsOf: paths.pinRecord))
    }

    public func verify(paths: InstallerPaths) throws -> PinRecord {
        let pin = try loadPin(paths: paths)
        guard pin.formatVersion == 2,
              Set(pin.supportedBuilds) == supportedBuildNumbers,
              pin.toolkitCommit == "69818621da1c850a28ef9aa023126338d65ffc1b",
              pin.toolkitGitTree == "97aa2128a035eeaa9be5bf87664999618fa0b2e7",
              pin.asarPackageVersion == "4.1.0",
              !pin.asarPackageIntegrity.isEmpty,
              pin.bundledNodeVersion == "v24.21.0",
              pin.bundledNodeUpstreamSHA256 == "e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b",
              pin.payloadFiles.keys.contains("pet/\(paths.product.petID)/pet.json"),
              pin.payloadFiles.keys.contains("pet/\(paths.product.petID)/\(paths.product.spritesheetFilename)"),
              pin.payloadFiles.keys.contains("capabilities/\(paths.product.capabilityKey)/sleep-strip.png") else {
            throw InstallerError.message("Bundled pin record is incomplete")
        }
        for (relative, expected) in pin.payloadFiles {
            let file = paths.payloadRoot.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: file.path) else { throw InstallerError.message("Missing payload file: \(relative)") }
            let actual = try Hashing.sha256(file)
            guard actual == expected else { throw InstallerError.message("Payload hash mismatch: \(relative)") }
        }
        guard FileManager.default.isExecutableFile(atPath: paths.bundledNode.path),
              try Hashing.sha256(paths.bundledNode) == pin.bundledNodeSHA256 else {
            throw InstallerError.message("Bundled Node runtime is missing or mismatched")
        }
        guard FileManager.default.fileExists(atPath: paths.nodeProvenanceManifest.path),
              try Hashing.sha256(paths.nodeProvenanceManifest) == pin.nodeProvenanceManifestSHA256 else {
            throw InstallerError.message("Bundled Node provenance manifest is missing or mismatched")
        }
        guard FileManager.default.fileExists(atPath: paths.thirdPartyNotices.path),
              try Hashing.sha256(paths.thirdPartyNotices) == pin.thirdPartyNoticesSHA256 else {
            throw InstallerError.message("Bundled third-party notices are missing or mismatched")
        }
        guard FileManager.default.fileExists(atPath: paths.toolkitFileManifest.path),
              try Hashing.sha256(paths.toolkitFileManifest) == pin.toolkitFileManifestSHA256,
              pin.toolkitTreeSHA256 == pin.toolkitFileManifestSHA256 else {
            throw InstallerError.message("Bundled enhancer file manifest is missing or mismatched")
        }
        for line in try String(contentsOf: paths.toolkitFileManifest, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2 else { throw InstallerError.message("Bundled enhancer file manifest is malformed") }
            let relative = String(fields[1]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "./", with: "", options: [.anchored])
            let file = paths.bundledToolkit.appendingPathComponent(relative)
            guard file.standardizedFileURL.path.hasPrefix(paths.bundledToolkit.standardizedFileURL.path + "/"),
                  FileManager.default.fileExists(atPath: file.path),
                  try Hashing.sha256(file) == String(fields[0]) else {
                throw InstallerError.message("Bundled enhancer tree mismatch: \(relative)")
            }
        }
        return pin
    }

    public func verifyPet(at directory: URL, expected: [String: String], petID: String = prototypePetID) throws -> Bool {
        for (name, hash) in expected where name.hasPrefix("pet/\(petID)/") {
            let basename = URL(fileURLWithPath: name).lastPathComponent
            let file = directory.appendingPathComponent(basename)
            guard FileManager.default.fileExists(atPath: file.path), try Hashing.sha256(file) == hash else { return false }
        }
        return true
    }
}
