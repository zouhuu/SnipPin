// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnipPin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SnipPin", targets: ["SnipPin"])
    ],
    targets: [
        .executableTarget(
            name: "SnipPin",
            path: "Sources/SnipPin",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
