// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SyncLab", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "SyncLab", targets: ["SyncLab"])], targets: [.target(name: "SyncLab"), .executableTarget(name: "LabReplay", dependencies: ["SyncLab"]), .testTarget(name: "SyncLabTests", dependencies: ["SyncLab"])])
