// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AscentKit",
    defaultLocalization: "en",
    // macOS is only listed so the domain and views can be compiled and tested on a Mac.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AscentCore", targets: ["AscentCore"]),
        .library(name: "AscentUI", targets: ["AscentUI"]),
        .library(name: "AscentWidgetsUI", targets: ["AscentWidgetsUI"]),
    ],
    targets: [
        .target(name: "AscentCore"),
        .target(
            name: "AscentUI",
            dependencies: ["AscentCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "AscentWidgetsUI",
            dependencies: ["AscentCore", "AscentUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AscentCoreTests", dependencies: ["AscentCore"]),
        // Renders screens to PNG on a Mac (set SNAPSHOT_DIR); a quick look without a simulator.
        .testTarget(name: "AscentUISnapshots", dependencies: ["AscentUI", "AscentWidgetsUI", "AscentCore"],
                    swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
