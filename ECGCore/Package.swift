// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ECGCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ECGCore", targets: ["ECGCore"])
    ],
    targets: [
        .target(name: "ECGCore"),
        .testTarget(
            name: "ECGCoreTests",
            dependencies: ["ECGCore"]
        )
    ]
)
