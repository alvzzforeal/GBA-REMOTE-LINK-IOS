// swift-tools-version: 5.9
// Package.swift — GBALinkEmulator
//
// This manifest lets Xcode/SPM resolve the mGBA dependency automatically.
// The mGBA team publishes a Swift Package at:
//   https://github.com/mgba-emu/mgba  (tag: 0.10.x)
//
// If a prebuilt xcframework is preferred, replace the `.package` entry with
// a binary target pointing to the xcframework URL + checksum.

import PackageDescription

let package = Package(
    name: "GBALinkEmulator",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "GBALinkEmulator", targets: ["GBALinkEmulator"])
    ],
    dependencies: [
        // ── mGBA ──────────────────────────────────────────────────────────
        // Option A: Source build from the official mirror (slow first build).
        // Uncomment ONE option and comment out the other.
        //
        // .package(
        //     url: "https://github.com/mgba-emu/mgba.git",
        //     from: "0.10.3"
        // ),
        //
        // Option B: Prebuilt xcframework (fast, requires hosting the artifact).
        // .package(
        //     url: "https://github.com/<your-org>/mgba-ios-xcframework.git",
        //     from: "0.10.3"
        // ),
    ],
    targets: [
        .target(
            name: "GBALinkEmulator",
            dependencies: [
                // .product(name: "mGBA", package: "mgba"),
            ],
            path: "GBALinkEmulator/GBALinkEmulator",
            exclude: [
                "Info.plist",
                "GBALinkEmulator-Bridging-Header.h",
            ],
            publicHeadersPath: "Bridge",
            cSettings: [
                .headerSearchPath("Bridge"),
            ],
            swiftSettings: [
                .unsafeFlags(["-import-objc-header",
                              "GBALinkEmulator/GBALinkEmulator/GBALinkEmulator-Bridging-Header.h"])
            ]
        ),
        .testTarget(
            name: "GBALinkEmulatorTests",
            dependencies: ["GBALinkEmulator"]
        )
    ]
)
