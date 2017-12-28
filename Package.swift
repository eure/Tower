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
    .library(
      name: "GitCommand",
      targets: ["GitCommand"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "1.2.1"),
    .package(url: "https://github.com/ReactiveX/RxSwift", .exact("4.0.0-beta.0")),
    .package(url: "https://github.com/muukii/Require.git", from: "1.1.0"),
    .package(url: "https://github.com/muukii/Bulk.git", from: "0.3.0"),
    .package(url: "https://github.com/kylef/PathKit.git", from: "0.8.0"),
    .package(url: "https://github.com/kylef/Commander.git", .exact("0.6.1")),
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
      name: "GitCommand"
    ),
    .target(
      name: "Tower",
      dependencies: [
        "Require",
        "Bulk",
        "ShellOut",
        "RxSwift",
        "PathKit",
        "GitCommand",
      ]),
    
    .testTarget(
      name: "TowerTests",
      dependencies: ["Tower"]),
  ]
)
