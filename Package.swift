// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "apple-reminders-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "apple-reminders-mcp", targets: ["AppleRemindersMCP"]),
        .library(name: "RemindersCore", targets: ["RemindersCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0"))
    ],
    targets: [
        // Pure logic: tool catalog, argument validation, date parsing, search matching.
        // No EventKit, so it is fully unit-testable.
        .target(
            name: "RemindersCore",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        ),
        // The EventKit-backed server and stdio bootstrap.
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: [
                "RemindersCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed an Info.plist so macOS can show the Reminders privacy prompt
                // for a bare command-line binary.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AppleRemindersMCP/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "RemindersCoreTests",
            dependencies: ["RemindersCore"]
        ),
    ]
)
