// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChargeNow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ChargeNow",
            path: "Sources/ChargeNow"
        )
    ]
)
