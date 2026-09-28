// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WatchBeatPeakSwiftBenchmark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PeakSwiftBenchmark", targets: ["PeakSwiftBenchmark"])
    ],
    dependencies: [
        // Exact released versions are required here. Package.resolved records the reviewed full
        // commit SHAs; never replace either requirement with a branch.
        .package(url: "https://github.com/CardioKit/PeakSwift.git", exact: "1.0.0"),
        // PeakSwift declares a broad Surge 2.x range. This direct exact constraint prevents a
        // future resolver run from silently benchmarking different transitive source.
        .package(url: "https://github.com/Jounce/Surge.git", exact: "2.3.2")
    ],
    targets: [
        .target(
            name: "PeakSwiftBenchmarkSupport",
            dependencies: [
                .product(name: "PeakSwift", package: "PeakSwift")
            ]
        ),
        .executableTarget(
            name: "PeakSwiftBenchmark",
            dependencies: ["PeakSwiftBenchmarkSupport"]
        ),
        .testTarget(
            name: "PeakSwiftBenchmarkSupportTests",
            dependencies: ["PeakSwiftBenchmarkSupport"]
        )
    ]
)
