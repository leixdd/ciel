// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CIEL",
    platforms: [.macOS(.v13)],
    targets: [
        // tools-version 5.9 ⇒ Swift 5 language mode by default (no strict concurrency).
        .executableTarget(name: "CIEL")
    ]
)
