// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gong",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑层：模型、时间投影、存储、reducer。可单元测试，不含 UI。
        .target(
            name: "GongCore",
            path: "Sources/GongCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // 审查要求：Swift 5 模式下显式开启完整并发检查，
                // 否则 Sendable / actor 隔离漏检。
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "Gong",
            dependencies: ["GongCore"],
            path: "Sources/Gong",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GongCoreTests",
            dependencies: ["GongCore"],
            path: "Tests/GongCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
