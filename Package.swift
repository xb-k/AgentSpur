// swift-tools-version: 5.9
// AgentSpur — 纯原生 macOS AppKit 菜单栏监控 (无 WebView · 零常驻守护进程 · opencode.db 只读)
import PackageDescription

let package = Package(
    name: "AgentSpur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentSpur", targets: ["AgentSpur"])
    ],
    targets: [
        .executableTarget(
            name: "AgentSpur",
            path: "Sources/AgentSpur",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
