// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MailApp",
    platforms: [.iOS("16.0")],
    targets: [
        .executableTarget(
            name: "MailApp",
            path: "."
        )
    ]
)
