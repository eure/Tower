// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Tower",
  products: [
    .executable(
      name: "towerd",
      targets: ["towerd"]
    ),
    .library(
      name: "Tower",
      targets: ["Tower"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/ReactiveX/RxSwift", .exact("4.1.0")),
    .package(url: "https://github.com/muukii/Require.git", from: "1.1.0"),
    .package(url: "https://github.com/muukii/Bulk.git", from: "0.4.0"),
    .package(url: "https://github.com/muukii/BulkSlackTarget.git", from: "0.2.0"),
    .package(url: "https://github.com/kylef/PathKit.git", from: "0.8.0"),
    .package(url: "https://github.com/kylef/Commander.git", .exact("0.6.1")),
    .package(url: "https://github.com/antitypical/Result.git", from: "3.2.4"),
  ],
  targets: [
    .target(
      name: "towerd",
      dependencies: [
        "Tower",
        "Commander",
        "PathKit",
      ]),
    .target(
      name: "Tower",
      dependencies: [
        "Require",
        "Bulk",
        "BulkSlackTarget",
        "RxSwift",
        "RxCocoa",
        "PathKit",
        "Result",
      ]),
    .testTarget(
      name: "TowerTests",
      dependencies: ["Tower"]),
  ]
)
