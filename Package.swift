// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PoolKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "PoolKit", targets: ["PoolKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "PoolKit",
            url: "https://github.com/ram-company/pool-kit/releases/download/0.3.0/PoolKit.xcframework.zip",
            checksum: "aec9eab3a96870f5ebd962a78f0dee7901145de5e12cf2f2803e61e402b59f2c"
        ),
    ]
)
