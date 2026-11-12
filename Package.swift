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
            url: "https://github.com/ram-company/pool-kit/releases/download/0.2.0/PoolKit.xcframework.zip",
            checksum: "9ebb4e3d1eaee0054313c66b6ba7c47478378d8f8688ba62cf5981eb8de1975a"
        ),
    ]
)
