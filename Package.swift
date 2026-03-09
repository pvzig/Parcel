// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Parcel",
  products: [
    .library(
      name: "Parcel",
      targets: ["Parcel"]
    )
  ],
  targets: [
    .target(
      name: "Parcel"
    ),
    .testTarget(
      name: "ParcelTests",
      dependencies: ["Parcel"]
    ),
  ]
)
