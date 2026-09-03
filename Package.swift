// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChargeMeNow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ChargeMeNow",
            path: "Sources/ChargeMeNow"
        )
    ]
)
