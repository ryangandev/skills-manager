// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SkillsManager",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "SkillsManager", targets: ["SkillsManager"]),
        .library(name: "SkillsCore", targets: ["SkillsCore"]),
    ],
    targets: [
        .target(
            name: "SkillsCore",
            path: "Sources/SkillsCore"
        ),
        .executableTarget(
            name: "SkillsManager",
            dependencies: ["SkillsCore"],
            path: "Sources/SkillsManager",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "SkillsCoreTests",
            dependencies: ["SkillsCore"],
            path: "Tests/SkillsCoreTests"
        ),
    ]
)
