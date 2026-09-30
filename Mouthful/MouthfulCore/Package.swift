// swift-tools-version: 5.9
import PackageDescription

// Foundation-only logic shared by the Mouthful macOS app (and a future iOS keyboard).
// Keeping this free of AppKit/AVFoundation means it can be unit-tested quickly with
// `swift test` from this directory, on any platform.
let package = Package(
  name: "MouthfulCore",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [
    .library(name: "MouthfulCore", targets: ["MouthfulCore"]),
  ],
  targets: [
    .target(name: "MouthfulCore"),
    .testTarget(name: "MouthfulCoreTests", dependencies: ["MouthfulCore"]),
  ]
)
