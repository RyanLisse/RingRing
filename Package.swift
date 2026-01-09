// swift-tools-version: 6.2
import Foundation
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableExperimentalFeature("RetroactiveConformances"),
]

let cliConcurrencySettings = concurrencySettings + [
    .defaultIsolation(MainActor.self),
]

let swiftTestingSettings = cliConcurrencySettings + [
    .enableExperimentalFeature("SwiftTesting"),
]

let package = Package(
    name: "ringring",
    platforms: [
        .macOS(.v14),  // macOS 14+ for Foundation async/await features
    ],
    products: [
        .executable(
            name: "phonecall",
            targets: ["PhoneCallExec"]
        ),
        .library(
            name: "RingRingCore",
            targets: ["RingRingCore"]
        ),
        .library(
            name: "RingRingCLI",
            targets: ["RingRingCLI"]
        ),
        .library(
            name: "RingRingMCP",
            targets: ["RingRingMCP"]
        ),
    ],
    dependencies: [
        // Commander for CLI
        .package(path: "../../Commander"),
        // MCP SDK
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        // Swift NIO for HTTP/WebSocket server
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.31.0"),
    ],
    targets: [
        // Core library - no CLI/MCP dependencies
        .target(
            name: "RingRingCore",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ],
            path: "Sources/Core",
            swiftSettings: concurrencySettings
        ),
        // CLI layer
        .target(
            name: "RingRingCLI",
            dependencies: [
                "RingRingCore",
                .product(name: "Commander", package: "Commander"),
            ],
            path: "Sources/CLI",
            swiftSettings: cliConcurrencySettings
        ),
        // MCP server
        .target(
            name: "RingRingMCP",
            dependencies: [
                "RingRingCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCP",
            swiftSettings: concurrencySettings
        ),
        // Executable entry point
        .executableTarget(
            name: "PhoneCallExec",
            dependencies: [
                "RingRingCLI",
                "RingRingMCP",
            ],
            path: "Sources/Executable",
            swiftSettings: cliConcurrencySettings
        ),
        // Tests
        .testTarget(
            name: "RingRingTests",
            dependencies: [
                "RingRingCore",
                "RingRingCLI",
            ],
            path: "Tests",
            swiftSettings: swiftTestingSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
