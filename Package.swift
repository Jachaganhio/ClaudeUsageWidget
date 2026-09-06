// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "UsageCore", targets: ["UsageCore"])],
    targets: [
        .target(name: "UsageCore", path: "Shared", exclude: ["UsageViews.swift"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ],
    swiftLanguageModes: [.v5]
)
