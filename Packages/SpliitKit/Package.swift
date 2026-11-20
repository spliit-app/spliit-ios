// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpliitKit",
    defaultLocalization: "en",
    // Apple deployment minimums; the core also builds with the Swift Android SDK.
    // macOS lets `swift test` run the unit suites without a simulator.
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SpliitAPI", targets: ["SpliitAPI"]),
        .library(name: "SpliitCore", targets: ["SpliitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", exact: "1.9.12"),
        .package(url: "https://github.com/skiptools/skip-fuse.git", exact: "1.0.3"),
    ],
    targets: [
        .target(name: "SpliitAPI"),
        .target(
            name: "SpliitCore",
            dependencies: [
                "SpliitAPI",
                // Skip's iOS prebuild must see this dependency to generate the Android
                // resource project's Gradle plugins and dependencies.
                .product(name: "SkipFuse", package: "skip-fuse"),
            ],
            // Standard .strings tables work with native SwiftPM on both Apple and Android.
            // Validation messages use this bundle rather than the app's translations.
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "SpliitAPITests",
            dependencies: ["SpliitAPI"],
            resources: [.copy("Fixtures")]
        ),
        // No recorded fixtures here: these suites build the legacy AsyncStorage layout in a
        // temporary directory, so the format under test is written out explicitly.
        .testTarget(name: "SpliitCoreTests", dependencies: ["SpliitCore"]),
    ]
)
