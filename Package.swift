// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OneLine",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OneLineCore", targets: ["OneLineCore"]),
        .executable(name: "OneLine", targets: ["OneLine"])
    ],
    targets: [
        .target(
            name: "OneLineCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "OneLine",
            dependencies: ["OneLineCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OneLineCoreTests",
            dependencies: ["OneLineCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
