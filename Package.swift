// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Daymark", platforms: [.macOS(.v13)], products: [.executable(name: "Daymark", targets: ["Notch"])], targets: [.executableTarget(name: "Notch"), .testTarget(name: "NotchTests", dependencies: ["Notch"])])
