// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncFoundation",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SyncFoundation", targets: ["SyncFoundation"]),
               .executable(name: "SyncSchema", targets: ["SyncSchema"]),
               .executable(name: "SyncPayloadProbe", targets: ["SyncPayloadProbe"]),
               .library(name: "FormalProbeCore", targets: ["FormalProbeCore"]),
               .executable(name: "FormalDevelopmentProbe", targets: ["FormalDevelopmentProbe"]),
               .executable(name: "FormalDevelopmentHost", targets: ["FormalDevelopmentHost"])],
    targets: [.target(name: "SyncFoundation"),
              .target(name: "FormalProbeCore", dependencies: ["SyncFoundation"]),
              .target(name: "FormalDevelopmentSDK", dependencies: ["FormalProbeCore", "SyncFoundation"]),
              .executableTarget(name: "FormalDevelopmentHost", dependencies: ["FormalDevelopmentSDK"]),
              .testTarget(name: "FormalDevelopmentSDKTests", dependencies: ["FormalDevelopmentSDK", "FormalProbeCore", "SyncFoundation"]),
              .executableTarget(name: "FormalDevelopmentProbe", dependencies: ["FormalProbeCore", "SyncFoundation"]),
              .testTarget(name: "FormalProbeCoreTests", dependencies: ["FormalProbeCore", "SyncFoundation"]), .executableTarget(name: "SyncSchema", dependencies: ["SyncFoundation"]), .executableTarget(name: "SyncPayloadProbe", dependencies: ["SyncFoundation"]), .testTarget(name: "SyncFoundationTests", dependencies: ["SyncFoundation"])]
)
