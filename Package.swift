// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "VoiceControl",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git",
      revision: "2ea0727541135c34189194084531337a3518e1bf"
    ),
    .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5"),
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
  ],
  targets: [
    .executableTarget(
      name: "VoiceControlDaemon",
      dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "TOMLDecoder", package: "TOMLDecoder"),
      ],
      path: "Sources/VoiceControlDaemon"
    ),
    .testTarget(
      name: "VoiceControlDaemonTests",
      dependencies: [
        "VoiceControlDaemon",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/VoiceControlDaemonTests"
    ),
  ],
  swiftLanguageModes: [.v5]
)
