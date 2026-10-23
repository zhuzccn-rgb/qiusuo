// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lexicon",
    defaultLocalization: "zh-Hans",
    platforms: [
        // 15 起才有 ToolbarContent.hidden(_:)，换页时靠它保持工具栏项不增删（否则顶栏会闪）。
        // swift-tools 5.9 的枚举只到 .v14，用字符串写法。
        .macOS("15.0")
    ],
    products: [
        .executable(name: "求索", targets: ["Lexicon"]),
        .library(name: "LexiconCore", targets: ["LexiconCore"]),
        .library(name: "LexiconSpeech", targets: ["LexiconSpeech"]),
        .library(name: "LexiconLLM", targets: ["LexiconLLM"]),
        .library(name: "LexiconInbox", targets: ["LexiconInbox"]),
        .library(name: "LexiconCalendar", targets: ["LexiconCalendar"])
    ],
    targets: [
        .target(
            name: "LexiconCore",
            path: "Sources/LexiconCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "LexiconSpeech",
            dependencies: ["LexiconCore"],
            path: "Sources/LexiconSpeech",
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "LexiconLLM",
            dependencies: ["LexiconCore"],
            path: "Sources/LexiconLLM",
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        ),
        .target(
            name: "LexiconInbox",
            dependencies: ["LexiconCore"],
            path: "Sources/LexiconInbox",
            linkerSettings: [
                .linkedFramework("CoreServices"),
                .linkedFramework("Vision"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "LexiconCalendar",
            dependencies: ["LexiconCore"],
            path: "Sources/LexiconCalendar",
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .executableTarget(
            name: "Lexicon",
            dependencies: [
                "LexiconCore",
                "LexiconSpeech",
                "LexiconLLM",
                "LexiconInbox",
                "LexiconCalendar"
            ],
            path: "App",
            exclude: ["Info.plist", "Lexicon.entitlements", "AppIcon.icns", "tex-svg.js"],
            linkerSettings: [
                .linkedFramework("PDFKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("Vision"),
                .linkedFramework("FoundationModels")
            ]
        ),
        .testTarget(
            name: "LexiconCoreTests",
            dependencies: ["LexiconCore"],
            path: "Tests/LexiconCoreTests"
        ),
        .testTarget(
            name: "LexiconSpeechTests",
            dependencies: ["LexiconSpeech", "LexiconCore"],
            path: "Tests/LexiconSpeechTests"
        ),
        .testTarget(
            name: "LexiconInboxTests",
            dependencies: ["LexiconInbox", "LexiconCore"],
            path: "Tests/LexiconInboxTests"
        ),
        .testTarget(
            name: "LexiconLLMTests",
            dependencies: ["LexiconLLM", "LexiconCore"],
            path: "Tests/LexiconLLMTests"
        ),
        .testTarget(
            name: "LexiconCalendarTests",
            dependencies: ["LexiconCalendar", "LexiconCore"],
            path: "Tests/LexiconCalendarTests"
        )
    ]
)
