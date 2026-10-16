// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevMissionControl",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DevControlCore"),
        .executableTarget(
            name: "DevMissionControl",
            dependencies: ["DevControlCore"]
        ),
        .executableTarget(
            name: "DevControlLogicTests",
            dependencies: ["DevControlCore"]
        )
    ]
)
