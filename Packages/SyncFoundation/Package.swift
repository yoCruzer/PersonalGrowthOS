// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncFoundation",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SyncFoundation", targets: ["SyncFoundation"]),
               .executable(name: "SyncSchema", targets: ["SyncSchema"])],
    targets: [.target(name: "SyncFoundation"), .executableTarget(name: "SyncSchema", dependencies: ["SyncFoundation"]), .testTarget(name: "SyncFoundationTests", dependencies: ["SyncFoundation"])]
)
