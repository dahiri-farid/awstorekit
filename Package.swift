// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AWStoreKit",
    platforms: [
        .iOS("16.6")
    ],
    products: [
        .library(
            name: "AWStoreKit",
            targets: ["AWStoreKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.33.1"),
        .package(url: "git@github.com:dahiri-farid/AWLogger.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "AWStoreKit",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
                .product(name: "AWLogger", package: "AWLogger"),
            ]
        )
    ]
)
