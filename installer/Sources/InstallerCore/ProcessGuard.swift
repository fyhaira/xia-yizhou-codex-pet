import Foundation

public protocol ProcessListing: Sendable { func processLines() throws -> [String] }

public struct ProcessRuntimeFacts: Sendable {
    public let executablePath: String?
    public let writablePaths: [String]
    public init(executablePath: String?, writablePaths: [String]) {
        self.executablePath = executablePath
        self.writablePaths = writablePaths
    }
}

public protocol ProcessRuntimeInspecting: Sendable {
    func facts(pid: Int32) throws -> ProcessRuntimeFacts?
}

public struct SystemProcessList: ProcessListing {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning = SystemCommandRunner()) { self.runner = runner }
    public func processLines() throws -> [String] {
        let result = try runner.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid=,ppid=,command="], environment: nil)
        if result.exitCode != 0 { throw InstallerError.message("Process inspection failed: \(result.stderr)") }
        return result.stdout.split(separator: "\n").map(String.init)
    }
}

public struct SystemProcessRuntimeInspector: ProcessRuntimeInspecting {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func facts(pid: Int32) throws -> ProcessRuntimeFacts? {
        let result = try runner.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-n", "-P", "-p", String(pid), "-Ffan"], environment: nil)
        guard result.exitCode == 0 else { return nil }
        var descriptor = "", access = "", executable: String?
        var writable: [String] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "f": descriptor = value; access = ""
            case "a": access = value.trimmingCharacters(in: .whitespaces)
            case "n":
                if descriptor == "txt", executable == nil, value.hasPrefix("/") { executable = value }
                if (access.contains("w") || access.contains("u")), value.hasPrefix("/") { writable.append(value) }
            default: break
            }
        }
        return ProcessRuntimeFacts(executablePath: executable, writablePaths: writable)
    }
}

public struct ProcessGuard: Sendable {
    private let listing: any ProcessListing
    private let runtimeInspector: any ProcessRuntimeInspecting
    public init(listing: any ProcessListing = SystemProcessList(), runtimeInspector: any ProcessRuntimeInspecting = SystemProcessRuntimeInspector()) {
        self.listing = listing
        self.runtimeInspector = runtimeInspector
    }

    public func blockers(paths: InstallerPaths, ownPID: Int32 = getpid()) throws -> [ProcessBlocker] {
        let officialRoots = [
            "/Applications/ChatGPT.app/",
            "/Applications/Codex.app/",
        ]
        let managedRoots = [
            paths.runtimeApp.path + "/",
            paths.protectedDailyLauncher.path + "/",
            paths.protectedDailySupport.path + "/",
        ]
        let protectedStateRoots = [
            paths.codexHome.path + "/",
            paths.protectedDailySupport.path + "/",
            paths.supportRoot.path + "/",
            paths.home.appendingPathComponent("Library/Application Support/Codex", isDirectory: true).path + "/",
            paths.home.appendingPathComponent("Library/Preferences/com.openai.codex.plist").path,
        ]
        let diagnosticMarkers = ["Codex-Gaze-Lab", "Codex-Drag-Diagnostics", "Codex-Pet-Runtime-", "-QA.app/", "Codex-9922-Unmodified"]
        return try listing.processLines().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let pieces = trimmed.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard pieces.count == 3, let pid = Int32(pieces[0]), pid != ownPID else { return nil }
            let command = String(pieces[2])
            if let root = officialRoots.first(where: { command.contains($0) }) {
                return ProcessBlocker(pid: pid, command: root.dropLast().description, reason: "Installed Codex/ChatGPT application is active")
            }
            if let root = managedRoots.first(where: { command.contains($0) }) {
                let display = root.replacingOccurrences(of: paths.home.path, with: "~")
                return ProcessBlocker(pid: pid, command: display, reason: "Codex process under \(URL(fileURLWithPath: root).lastPathComponent)")
            }
            if let marker = diagnosticMarkers.first(where: command.contains) {
                return ProcessBlocker(pid: pid, command: marker, reason: "QA or diagnostic Codex process")
            }
            if command.localizedCaseInsensitiveContains("codex app-server") || command.contains("/codex app-server") {
                return ProcessBlocker(pid: pid, command: "codex app-server", reason: "Codex app-server is active")
            }
            let couldBeAmbiguousChatGPT = command.contains("ChatGPTHelper") || command.hasPrefix("/Applications/ChatGPT")
            if couldBeAmbiguousChatGPT {
                guard let facts = try runtimeInspector.facts(pid: pid) else {
                    return ProcessBlocker(pid: pid, command: "unresolved ChatGPT helper", reason: "Could not safely resolve ChatGPT helper ownership")
                }
                if let executable = facts.executablePath,
                   officialRoots.contains(where: executable.hasPrefix) {
                    return ProcessBlocker(pid: pid, command: executable, reason: "Official Codex/ChatGPT helper is active")
                }
                if let written = facts.writablePaths.first(where: { path in protectedStateRoots.contains(where: path.hasPrefix) }) {
                    let display = written.replacingOccurrences(of: paths.home.path, with: "~")
                    return ProcessBlocker(pid: pid, command: display, reason: "Process has a writable handle in protected Codex state")
                }
            }
            return nil
        }
    }

    public func requireClean(paths: InstallerPaths) throws {
        let found = try blockers(paths: paths)
        if !found.isEmpty {
            let details = found.map { "PID \($0.pid): \($0.reason)" }.joined(separator: ", ")
            throw InstallerError.message("Quit all Codex, Toolkit, QA, and diagnostic processes before continuing. \(details)")
        }
    }
}
