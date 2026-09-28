// swift-tools-version: 5.9
import PackageDescription

// Foundation-only logic shared by the Dictum macOS app (and a future iOS keyboard).
// Keeping this free of AppKit/AVFoundation means it can be unit-tested quickly with
// `swift test` from this directory, on any platform.
let package = Package(
  name: "DictumCore",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [
    .library(name: "DictumCore", targets: ["DictumCore"]),
  ],
  targets: [
    .target(name: "DictumCore"),
    .testTarget(name: "DictumCoreTests", dependencies: ["DictumCore"]),
  ]
)
