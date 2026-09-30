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
    targets: [
        .target(name: "SpliitAPI"),
        .target(
            name: "SpliitCore",
            dependencies: ["SpliitAPI"],
            // Standard .strings tables work with native SwiftPM on both Apple and Android.
            // Validation messages use this bundle rather than the app's translations.
            resources: [.process("Resources")]
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
