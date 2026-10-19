// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "HaloCore", targets: ["HaloCore"]),
        .executable(name: "Halo", targets: ["Halo"])
    ],
    targets: [
        .target(
            name: "HaloCore",
            path: "Sources/HaloCore"
        ),
        .executableTarget(
            name: "Halo",
            dependencies: ["HaloCore"],
            path: "Sources/Halo"
        ),
        .testTarget(
            name: "HaloCoreTests",
            dependencies: ["HaloCore"],
            path: "Tests/HaloCoreTests"
        )
    ]
)
