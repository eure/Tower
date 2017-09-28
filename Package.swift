// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Tower",
  products: [
    // Products define the executables and libraries produced by a package, and make them visible to other packages.
    .executable(
      name: "towerd",
      targets: ["towerd"]),
    .library(
      name: "Tower",
      targets: ["towerd"]),
  ],
  dependencies: [
      // Dependencies declare other packages that this package depends on.
      // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "1.2.1"),
    .package(url: "https://github.com/ReactiveX/RxSwift", .exact("4.0.0-beta.0")),
    .package(url: "https://github.com/muukii/Require.git", from: "1.1.0"),
    .package(url: "https://github.com/muukii/Bulk.git", from: "0.3.0"),
    .package(url: "https://github.com/kylef/PathKit.git", from: "0.8.0"),
  ],
  targets: [
    .target(
      name: "towerd",
      dependencies: [
        "Tower",
      ]),
    .target(
      name: "Tower",
      dependencies: [
        "Require",
        "Bulk",
        "ShellOut",
        "RxSwift",
        "PathKit",
      ]),
    .testTarget(
      name: "TowerTests",
      dependencies: ["Tower"]),
  ]
)
