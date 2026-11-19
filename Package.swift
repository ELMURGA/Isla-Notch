// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Isla",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Isla",
            path: "Sources/Isla",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
