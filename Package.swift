// swift-tools-version: 5.9
import PackageDescription
import Foundation

var targets: [Target] = [
    .target(
        name: "AvafliSDK",
        path: "AvafliSDK",
        resources: [
            .process("Resources")
        ]
    )
]

// The public mirror ships without the test suite, and a declared test target
// whose directory is missing makes `swift build` fail in a fresh clone of the
// mirror. Declare it only where the directory actually exists (the private
// monorepo), so this one manifest is correct in both repos.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/AvafliSDKTests") {
    targets.append(
        .testTarget(
            name: "AvafliSDKTests",
            dependencies: ["AvafliSDK"],
            path: "AvafliSDKTests"
        )
    )
}

let package = Package(
    name: "AvafliSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AvafliSDK",
            targets: ["AvafliSDK"]
        )
    ],
    targets: targets
)
