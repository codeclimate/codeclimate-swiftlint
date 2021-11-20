// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "codeclimate-SwiftLint",
    platforms: [.macOS(.v10_12)],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint.git", .exact("0.45.0"))
    ],
    targets: [
        .executableTarget(
            name: "codeclimate-SwiftLint",
            dependencies: [
                .product(name: "SwiftLintFramework", package: "SwiftLint")
            ]
        )
    ]
)
