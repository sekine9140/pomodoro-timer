// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MailApp",
    platforms: [.iOS("17.0")],
    products: [
        .library(name: "MailApp", targets: ["MailApp"])
    ],
    targets: [
        .target(
            name: "MailApp",
            path: ".",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
