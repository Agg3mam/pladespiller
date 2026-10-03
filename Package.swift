// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pladespiller",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Pladespiller",
            path: "Sources/Pladespiller",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
