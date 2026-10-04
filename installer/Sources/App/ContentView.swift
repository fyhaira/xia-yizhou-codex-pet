import InstallerCore
import SwiftUI

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published var title = "Welcome"
    @Published var detail = "Review compatibility, run a dry check, then install the selected pet package."
    @Published var busy = false
    @Published var installed = false
    @Published var productName = "Xia Yizhou Codex Pet"
    private var service: InstallerService?
    private var initializationError: String?

    init() {
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        do {
            let paths = try InstallerPaths.live(resources: resources)
            productName = paths.product.displayNameEnglish
            service = InstallerService(paths: paths)
            refresh()
        }
        catch { service = nil; initializationError = error.localizedDescription; title = "Unsupported Package"; detail = error.localizedDescription }
    }

    func refresh() {
        guard !busy else { return }
        guard let service else { title = "Unsupported Package"; detail = initializationError ?? "Product configuration is unavailable"; return }
        busy = true; title = "Compatibility status"
        Task {
            let outcome = await Task.detached { () -> (PreflightReport?, String?) in
                do { return (try service.preflight(), nil) } catch { return (nil, error.localizedDescription) }
            }.value
            if let report = outcome.0 {
                installed = report.prototypeInstalled
                let version = [report.version, report.build.map { "build \($0)" }].compactMap { $0 }.joined(separator: " / ")
                let blocker = report.blockers.isEmpty ? "No blocking Codex process detected." : "Codex is still running (\(report.blockers.count) blocking process(es))."
                detail = "\(report.state.rawValue): \(version.isEmpty ? "no official app" : version)\n\(blocker)\nDaily-use Toolkit detected: \(report.dailyUseToolkitPresent ? "yes — protected" : "no")"
            } else { title = "Error / rollback result"; detail = outcome.1 ?? "Unknown preflight error" }
            busy = false
        }
    }

    func dryRun() { guard let service else { return }; perform("Dry Run") { let report = try service.dryRun(); return report.plannedChanges.map { "• \($0)" }.joined(separator: "\n") + "\n\nNo files were changed." } }
    func install() { guard let service else { return }; perform("Installing") { _ = try service.install(launchAfterInstall: true); return "Installation and verification succeeded. The managed runtime was launched with the normal shared profile." } }
    func reconcileIdentity() { guard let service else { return }; perform("Reconciling Identity") { _ = try service.reconcileVerifiedIdentityAlias(launchAfterRebuild: true); return "The migrated pet identity was verified and the managed runtime was rebuilt with a bounded capability alias." } }
    func verify() { guard let service else { return }; perform("Verification") { let report = try service.verify(); return "Pet: \(report.petValid ? "valid" : "invalid")\nRuntime: \(report.runtimePresent ? "present" : "missing")\nSelection: \(report.configSelected ? "correct" : "not selected")\nMetadata: \(report.metadataValid ? "valid" : "invalid")" } }
    func launch() { guard let service else { return }; perform("Launch") { try service.launch(); return "Managed runtime launched." } }
    func uninstall() { guard let service else { return }; perform("Uninstall") { try service.uninstall(); return "Installer-owned runtime and pet state were removed. Pre-existing pet packages and unrelated Codex data were preserved." } }

    private func perform(_ heading: String, work: @escaping @Sendable () throws -> String) {
        guard !busy else { return }
        busy = true; title = heading
        Task {
            let outcome = await Task.detached { () -> (Bool, String) in
                do { return (true, try work()) } catch { return (false, error.localizedDescription) }
            }.value
            if outcome.0 {
                detail = outcome.1
                if heading == "Installing" { title = "Success"; installed = true }
                if heading == "Uninstall" { installed = false }
            } else {
                title = outcome.1.contains("unsupported") ? "Unsupported Build" : (outcome.1.contains("Quit all Codex") ? "Codex Still Running" : "Error / rollback result")
                detail = outcome.1
            }
            busy = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = InstallerViewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.productName).font(.title2).bold()
            Text(model.title).font(.headline)
            ScrollView { Text(model.detail).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(width: 520, height: 190)
                .padding(10).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Refresh") { model.refresh() }
                Button("Dry Run") { model.dryRun() }
                Button("Install \(model.productName)") { model.install() }.disabled(model.busy)
                Button("Verify Migrated Identity") { model.reconcileIdentity() }.disabled(!model.installed || model.busy)
            }
            HStack {
                Button("Verify") { model.verify() }
                Button("Launch Managed Runtime") { model.launch() }.disabled(!model.installed || model.busy)
                Button("Uninstall") { model.uninstall() }.disabled(!model.installed || model.busy)
            }
            Text("Developer Preview • exact builds 8881, 9922, 10789, 11431 • official ChatGPT.app is never patched")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 580, height: 390)
    }
}
