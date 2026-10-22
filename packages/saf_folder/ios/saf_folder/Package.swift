// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "saf_folder",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "saf-folder", targets: ["saf_folder"])
  ],
  dependencies: [],
  targets: [
    .target(name: "saf_folder", dependencies: [])
  ]
)
