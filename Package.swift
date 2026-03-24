// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jishu",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Jishu",
            targets: ["Jishu"]
        ),
    ],
    targets: [
        .target(
            name: "Jishu"
        ),
        .testTarget(
            name: "JishuTests",
            dependencies: ["Jishu"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
