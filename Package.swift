// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "tau",
    platforms: [
       .macOS(.v10_15),
    ],
    products: [
        .library(name: "Tau", targets: ["Tau"]),
    ],
    dependencies: [
        .package(url: "https://github.com/binarybirds/tau-kit", from: "1.0.0"),
        .package(url: "https://github.com/vapor/vapor", from: "4.41.0"),
    ],
    targets: [
        .target(name: "Tau", dependencies: [
            .product(name: "TauKit", package: "tau-kit"),
            .product(name: "Vapor", package: "vapor"),
        ]),
        .testTarget(name: "TauTests", dependencies: [
            .target(name: "Tau"),
            .product(name: "XCTVapor", package: "vapor"),
            .product(name: "XCTTauKit", package: "tau-kit"),
        ], exclude: [
            "Templates",
        ]),
    ]
)
