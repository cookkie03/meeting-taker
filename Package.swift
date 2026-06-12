// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "meeting-taker",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "meeting-taker",
            targets: ["MeetingTakerApp"]
        ),
        .executable(
            name: "mtaker",
            targets: ["MeetingTakerCLI"]
        ),
        .library(
            name: "MeetingTakerKit",
            targets: ["MeetingTakerKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.1"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.2"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.1"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "MeetingTakerKit",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/MeetingTakerKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // MARK: - SwiftUI App
        .executableTarget(
            name: "MeetingTakerApp",
            dependencies: [
                "MeetingTakerKit",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
            ],
            path: "Sources/MeetingTaker",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // MARK: - CLI Tool
        .executableTarget(
            name: "MeetingTakerCLI",
            dependencies: [
                "MeetingTakerKit",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
            ],
            path: "Sources/MeetingTakerCLI",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // MARK: - Tests
        .testTarget(
            name: "MeetingTakerTests",
            dependencies: [
                "MeetingTakerKit",
            ],
            path: "Tests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
