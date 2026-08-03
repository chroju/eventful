// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "eventful",
    // Deployment target kept low deliberately: this is a compile/lint floor
    // for CI (whose SDK lags the developer's own macOS), not a compatibility
    // promise. The actual minimum OS is enforced at runtime via
    // Info.plist's LSMinimumSystemVersion, which build.sh stamps with the
    // host's real macOS version.
    platforms: [
        .macOS("14")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "ntf",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ntfTests",
            dependencies: ["ntf"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
