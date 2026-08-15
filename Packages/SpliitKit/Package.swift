// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpliitKit",
    // The app only ships for iOS. macOS is declared so `swift test` runs the unit suites on
    // the host in a couple of seconds, with no simulator involved.
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SpliitAPI", targets: ["SpliitAPI"]),
        .library(name: "SpliitCore", targets: ["SpliitCore"]),
    ],
    targets: [
        .target(name: "SpliitAPI"),
        .target(name: "SpliitCore"),
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
