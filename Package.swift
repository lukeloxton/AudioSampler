// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioSampler",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AudioSampler",
            path: "Sources/AudioSampler"
        )
    ]
)
