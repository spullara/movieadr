// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MovieADR",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/kylehowells/demucs-mlx-swift", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "MovieADR",
            dependencies: [
                "WhisperKit",
                .product(name: "DemucsMLX", package: "demucs-mlx-swift"),
            ],
            path: "Sources"
        ),
    ]
)
