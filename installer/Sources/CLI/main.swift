import Foundation
import InstallerCore

func resourcesURL(arguments: inout [String]) -> URL {
    if let index = arguments.firstIndex(of: "--resources"), arguments.indices.contains(index + 1) {
        let value = arguments[index + 1]
        arguments.removeSubrange(index...index + 1)
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    if let bundle = Bundle.main.resourceURL,
       FileManager.default.fileExists(atPath: bundle.appendingPathComponent("metadata/pin.json").path) { return bundle }
    let executableResources = URL(fileURLWithPath: CommandLine.arguments[0])
        .standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: executableResources.appendingPathComponent("metadata/pin.json").path) {
        return executableResources
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources", isDirectory: true)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let resources = resourcesURL(arguments: &arguments)
let command = arguments.first ?? "preflight"
let encoder = JSONEncoder.pretty

do {
    let service = InstallerService(paths: try .live(resources: resources))
    switch command {
    case "preflight", "dry-run":
        let report = command == "dry-run" ? try service.dryRun() : try service.preflight()
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    case "verify": print(String(decoding: try encoder.encode(service.verify()), as: UTF8.self))
    case "install":
        let metadata = try service.install(launchAfterInstall: !arguments.contains("--no-launch"))
        print(String(decoding: try encoder.encode(metadata), as: UTF8.self))
    case "reconcile-identity":
        let metadata = try service.reconcileVerifiedIdentityAlias(launchAfterRebuild: !arguments.contains("--no-launch"))
        print(String(decoding: try encoder.encode(metadata), as: UTF8.self))
    case "launch": try service.launch(); print("Managed runtime launched")
    case "uninstall": try service.uninstall(); print("Xia Yizhou Codex Pet uninstalled")
    case "cleanup-uninstall-residue": try service.cleanupHistoricalUninstallResidue(); print("Historical installer uninstall residue cleaned")
    default: throw InstallerError.message("Usage: preflight|dry-run|verify|install [--no-launch]|reconcile-identity [--no-launch]|launch|uninstall|cleanup-uninstall-residue [--resources PATH]")
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
