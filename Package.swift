// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RouteWarriorKit",
    // macOS is here so `swift test` runs on a bare macOS runner — no simulator
    // needed. That is the whole point of keeping the kit UI-free.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RouteWarriorKit", targets: ["RouteWarriorKit"]),
        .library(name: "RouteWarriorStore", targets: ["RouteWarriorStore"]),
    ],
    targets: [
        // RouteWarriorKit is UI-free: no UIKit, SwiftUI, or any other UI
        // framework. scripts/kit-purity-gate.sh enforces this in CI. Every
        // rule of the app lives here; the app target only renders it.
        .target(name: "RouteWarriorKit"),
        // RouteWarriorStore holds the SwiftData persistence layer (M2+),
        // mapping the kit's value types to persisted models. Kept separate so
        // persistence concerns never leak into algorithm tests.
        .target(name: "RouteWarriorStore", dependencies: ["RouteWarriorKit"]),
        .testTarget(name: "RouteWarriorKitTests", dependencies: ["RouteWarriorKit"]),
        .testTarget(name: "RouteWarriorStoreTests", dependencies: ["RouteWarriorStore"]),
    ]
)
