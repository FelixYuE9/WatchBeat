// swift-tools-version: 5.9

import PackageDescription

// The shipping target is iOS 17. `.macOS(.v14)` is declared only so the same sources can be
// compiled and unit-tested on a Command Line Tools-only macOS host, where no iOS SDK exists.
// HealthKit ECG metadata is exposed by the macOS SDK from macOS 13, so the mapper and repository
// can be built and tested here. Runtime HealthKit behavior on macOS is NOT validated.
//
// `WatchBeatModels` and `WatchBeatHealthKit` are SwiftUI-free so they can also be compiled with an
// iOS triple (Mac Catalyst slice of the macOS SDK). The SwiftUI module `WatchBeatApp` cannot: this
// SDK has no Catalyst slice for SwiftUI.
let package = Package(
    name: "WatchBeatApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "WatchBeatKit", targets: ["WatchBeatModels", "WatchBeatHealthKit"]),
        .library(name: "WatchBeatApp", targets: ["WatchBeatApp"])
    ],
    dependencies: [
        .package(path: "../ECGCore")
    ],
    targets: [
        .target(
            name: "WatchBeatModels",
            dependencies: [
                .product(name: "ECGCore", package: "ECGCore")
            ],
            path: "Models"
        ),
        .target(
            name: "WatchBeatHealthKit",
            dependencies: [
                "WatchBeatModels",
                .product(name: "ECGCore", package: "ECGCore")
            ],
            path: "HealthKit",
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        ),
        .target(
            name: "WatchBeatApp",
            dependencies: [
                "WatchBeatModels",
                "WatchBeatHealthKit"
            ],
            path: ".",
            exclude: [
                "Models",
                "HealthKit",
                "Tests",
                "Resources",
                "README.md",
                "Package.swift"
            ]
        ),
        .testTarget(
            name: "WatchBeatAppTests",
            dependencies: [
                "WatchBeatModels",
                "WatchBeatHealthKit",
                .product(name: "ECGCore", package: "ECGCore")
            ],
            path: "Tests",
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        )
    ]
)
