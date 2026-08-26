// swift-tools-version: 6.4

import Foundation
import PackageDescription

let wasmTestingLinkerFlags: [LinkerSetting] = [
    .unsafeFlags(
        [
            "-Xlinker", "--stack-first",
            "-Xlinker", "--global-base=524288",
            "-Xlinker", "-z",
            "-Xlinker", "stack-size=524288",
        ],
        .when(platforms: [.wasi])
    )
]

let includeWasmBrowserTests =
    ProcessInfo.processInfo.environment["PARCEL_INCLUDE_WASM_TESTS"] == "1"
let enableWasmHTTPClient =
    ProcessInfo.processInfo.environment["HTTP_API_ENABLE_WASM"] != nil

if includeWasmBrowserTests && enableWasmHTTPClient == false {
    fatalError("PARCEL_INCLUDE_WASM_TESTS=1 requires HTTP_API_ENABLE_WASM=1")
}

var parcelDependencies: [Target.Dependency] = [
    .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
    .product(name: "HTTPTypes", package: "swift-http-types"),
]

if enableWasmHTTPClient {
    parcelDependencies.append(contentsOf: [
        .product(
            name: "FetchHTTPClient",
            package: "swift-http-api-proposal",
            condition: .when(platforms: [.wasi])
        ),
        .product(
            name: "JavaScriptEventLoop",
            package: "JavaScriptKit",
            condition: .when(platforms: [.wasi])
        ),
    ])
}

var packageTargets: [Target] = [
    .target(
        name: "Parcel",
        dependencies: parcelDependencies
    )
]

if includeWasmBrowserTests {
    packageTargets.append(
        .testTarget(
            name: "ParcelBrowserTests",
            dependencies: [
                "Parcel",
                // PackageToJS discovers BridgeJS bindings through direct test-target dependencies.
                .product(name: "FetchHTTPClient", package: "swift-http-api-proposal"),
                .product(name: "JavaScriptEventLoopTestSupport", package: "JavaScriptKit"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            linkerSettings: wasmTestingLinkerFlags
        )
    )
} else {
    packageTargets.append(
        .testTarget(
            name: "ParcelHostTests",
            dependencies: [
                "Parcel",
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
            ]
        )
    )
}

let package = Package(
    name: "Parcel",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Parcel",
            targets: ["Parcel"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
        .package(
            url: "https://github.com/apple/swift-http-api-proposal.git",
            revision: "5a0eb4340a4f0875a59a5aef9e4fe6c307fbd1e7"
        ),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.58.0"),
    ],
    targets: packageTargets
)
