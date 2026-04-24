// swift-tools-version: 6.3

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

var packageTargets: [Target] = [
  .target(
    name: "Parcel",
    dependencies: [
      .product(name: "HTTPTypes", package: "swift-http-types"),
      .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
      .product(name: "JavaScriptKit", package: "JavaScriptKit"),
    ]
  ),
  .testTarget(
    name: "ParcelHostTests",
    dependencies: ["Parcel"]
  ),
]

if includeWasmBrowserTests {
  packageTargets.append(
    .testTarget(
      name: "ParcelBrowserTests",
      dependencies: [
        "Parcel",
        .product(name: "JavaScriptEventLoopTestSupport", package: "JavaScriptKit"),
        .product(name: "JavaScriptKit", package: "JavaScriptKit"),
      ],
      linkerSettings: wasmTestingLinkerFlags
    )
  )
}

let package = Package(
  name: "Parcel",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "Parcel",
      targets: ["Parcel"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.50.2"),
  ],
  targets: packageTargets
)
