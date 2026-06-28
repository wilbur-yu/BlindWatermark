// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlindWatermark",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "BlindWatermark",
            path: "Sources/BlindWatermark"
        )
    ]
)
