// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MoonlightClient",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "MoonlightClient", targets: ["MoonlightClient"]),
        .executable(name: "MoonlightControlProbe", targets: ["MoonlightControlProbe"]),
        .executable(name: "MoonlightSessionProbe", targets: ["MoonlightSessionProbe"]),
    ],
    targets: [
        .binaryTarget(
            name: "OpenSSL",
            path: "Vendor/OpenSSL/OpenSSL.xcframework"
        ),
        .binaryTarget(
            name: "Opus",
            path: "Vendor/Opus/Opus.xcframework"
        ),
        .target(
            name: "COpenSSL",
            dependencies: ["OpenSSL"],
            path: "Sources/COpenSSL",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "COpus",
            dependencies: ["Opus"],
            path: "Sources/COpus",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CMoonlightCore",
            dependencies: ["COpenSSL"],
            path: "Sources/CMoonlightCore",
            exclude: [
                "nanors/t",
                "nanors/rs16.c",
                "nanors/rs16_afft.c",
                "nanors/deps/obl/oblas16.c",
                "nanors/deps/obl/oblas16_afft.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("common"),
                .headerSearchPath("enet/include"),
                .headerSearchPath("nanors"),
                .headerSearchPath("nanors/deps"),
                .headerSearchPath("nanors/deps/obl"),
                .define("NDEBUG"),
                .define("__APPLE_USE_RFC_3542"),
            ]
        ),
        .target(
            name: "MoonlightBridge",
            dependencies: ["CMoonlightCore", "COpenSSL", "COpus"],
            path: "Sources/MoonlightBridge",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Security"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .target(
            name: "MoonlightClient",
            dependencies: ["MoonlightBridge"],
            path: "Sources/MoonlightClient"
        ),
        .executableTarget(
            name: "MoonlightControlProbe",
            dependencies: ["MoonlightBridge", "CMoonlightCore"],
            path: "Sources/MoonlightControlProbe"
        ),
        .executableTarget(
            name: "MoonlightSessionProbe",
            dependencies: ["MoonlightBridge", "CMoonlightCore"],
            path: "Sources/MoonlightSessionProbe"
        ),
    ]
)
