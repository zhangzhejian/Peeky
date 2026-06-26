// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Peeky",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Peeky", targets: ["Peeky"])
    ],
    targets: [
        .executableTarget(
            name: "Peeky",
            path: "Sources/Peeky"
        )
    ]
)
