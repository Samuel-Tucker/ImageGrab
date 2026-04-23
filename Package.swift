// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageGrab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ImageGrabKit", targets: ["ImageGrabKit"]),
        .executable(name: "ImageGrab", targets: ["ImageGrab"])
    ],
    targets: [
        .target(
            name: "ImageGrabKit",
            path: "Sources/ImageGrab"
        ),
        .executableTarget(
            name: "ImageGrab",
            dependencies: ["ImageGrabKit"],
            path: "Sources/ImageGrabApp"
        ),
        .testTarget(
            name: "ImageGrabKitTests",
            dependencies: ["ImageGrabKit"],
            path: "Tests/ImageGrabKitTests"
        )
    ]
)
