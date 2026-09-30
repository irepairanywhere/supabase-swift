// swift-tools-version: 5.10
import PackageDescription

// The macOS app. Build a runnable .app bundle with `make app` (see Makefile / scripts/build-app.sh),
// or generate an Xcode project with `make xcodeproj` (needs XcodeGen).
let package = Package(
  name: "Mouthful",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "MouthfulCore"),
    // WhisperKit lives in the renamed argmax-oss-swift repository. The old
    // github.com/argmaxinc/WhisperKit URL redirects here.
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
  ],
  targets: [
    .executableTarget(
      name: "Mouthful",
      dependencies: [
        .product(name: "MouthfulCore", package: "MouthfulCore"),
        .product(name: "WhisperKit", package: "argmax-oss-swift"),
      ],
      path: "Sources/Mouthful",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Speech"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
  ]
)
