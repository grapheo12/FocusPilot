// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusPilot",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FocusPilotCore", targets: ["FocusPilotCore"]),
        .library(name: "FocusPilotPlanner", targets: ["FocusPilotPlanner"]),
        .library(name: "FocusPilotVault", targets: ["FocusPilotVault"]),
        .executable(name: "FocusPilot", targets: ["FocusPilot"])
    ],
    targets: [
        .target(name: "FocusPilotCore"),
        .target(
            name: "FocusPilotPlanner",
            dependencies: ["FocusPilotCore"]
        ),
        .target(
            name: "FocusPilotVault",
            dependencies: ["FocusPilotCore"]
        ),
        .executableTarget(
            name: "FocusPilot",
            dependencies: ["FocusPilotCore", "FocusPilotPlanner", "FocusPilotVault"]
        ),
        .testTarget(
            name: "FocusPilotCoreTests",
            dependencies: ["FocusPilotCore"]
        ),
        .testTarget(
            name: "FocusPilotPlannerTests",
            dependencies: ["FocusPilotCore", "FocusPilotPlanner"]
        ),
        .testTarget(
            name: "FocusPilotVaultTests",
            dependencies: ["FocusPilotCore", "FocusPilotVault"]
        )
    ]
)
