// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Packagis",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "Packagis", targets: ["Packagis"]),
        .executable(name: "PackagisPrototype", targets: ["PackagisPrototype"]),
    ],
    targets: [
        .target(name: "Packagis"),
        .executableTarget(
            name: "PackagisPrototype",
            dependencies: ["Packagis"]
        ),
        .testTarget(
            name: "PackagisTests",
            dependencies: ["Packagis"]
        ),
    ]
)
