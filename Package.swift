// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "air-cc",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AirCCCore",
            targets: ["AirCCCore"]
        ),
        .executable(
            name: "air-cc",
            targets: ["AirCCApp"]
        )
    ],
    targets: [
        .target(
            name: "AirCCCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "AirCCApp",
            dependencies: ["AirCCCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "AirCCSelfTest",
            dependencies: ["AirCCCore"]
        )
    ]
)
