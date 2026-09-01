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
        // 可执行入口。产品对外叫「日课 / Rike」；**内部标识仍是 gong**
        // （bundle id、数据目录、导出文件里的 marker），改了会让既有数据与
        // 已导出文件失联，所以只改人看得见的名字。
        .executableTarget(
            name: "Rike",
            dependencies: ["GongCore"],
            path: "Sources/Rike",
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
