// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jishu",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Jishu",
            targets: ["Jishu"]
        ),
    ],
    targets: [
        .target(
            name: "Jishu",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("StoreKit")]
        ),
        .testTarget(
            name: "JishuTests",
            dependencies: ["Jishu"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
