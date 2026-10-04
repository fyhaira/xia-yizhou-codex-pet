// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XiaYizhouCodexPetInstaller",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InstallerCore", targets: ["InstallerCore"]),
        .executable(name: "xia-yizhou-codex-pet", targets: ["CLI"]),
        .executable(name: "XiaYizhouCodexPet", targets: ["App"]),
    ],
    targets: [
        .target(name: "InstallerCore", path: "Sources/InstallerCore"),
        .executableTarget(name: "CLI", dependencies: ["InstallerCore"], path: "Sources/CLI"),
        .executableTarget(name: "App", dependencies: ["InstallerCore"], path: "Sources/App"),
    ]
)
