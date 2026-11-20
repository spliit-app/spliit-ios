// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "spliit-ui",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SpliitUI", type: .dynamic, targets: ["SpliitUI"])],
    dependencies: [
        // The core's Skip plugin packages its validation-message resources for Android.
        .package(path: "Packages/SpliitKit"),
        .package(url: "https://github.com/skiptools/skip.git", exact: "1.9.12"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", exact: "1.18.3"),
    ],
    targets: [
        .target(
            name: "SpliitUI",
            dependencies: [
                .product(name: "SpliitAPI", package: "SpliitKit"),
                .product(name: "SpliitCore", package: "SpliitKit"),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            ],
            path: "Spliit",
            exclude: ["Info.plist", "Spliit.entitlements", "Resources/InfoPlist.xcstrings"],
            resources: [.process("Resources"), .process("PrivacyInfo.xcprivacy")],
            swiftSettings: [
                // Skip generates nonisolated generic-view bridges; isolate Android models explicitly.
                .defaultIsolation(MainActor.self, .when(platforms: [.iOS, .macOS])),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
