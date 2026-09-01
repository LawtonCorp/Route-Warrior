// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StarterKit",
    // macOS is here so `swift test` runs on a bare macOS runner — no simulator
    // needed. That is the whole point of keeping the kit UI-free.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StarterKit", targets: ["StarterKit"]),
    ],
    targets: [
        // StarterKit is UI-free: no UIKit, SwiftUI, or any other UI framework.
        // scripts/kit-purity-gate.sh enforces this in CI. Keep every rule of
        // the app here, and keep the app target a thin rendering layer.
        .target(name: "StarterKit"),
        .testTarget(name: "StarterKitTests", dependencies: ["StarterKit"]),
    ]
)
