// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DKST-macOS-Notary",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DKST-macOS-Notary", targets: ["DKST-macOS-Notary"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DKST-macOS-Notary",
            dependencies: [],
            path: "Sources",
            exclude: ["Resources"]
        )
    ]
)
