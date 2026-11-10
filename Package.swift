// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vigie",
    // macOS 14 (Sonoma) : minimum requis par l'API « Observation » de SwiftUI utilisée par l'app.
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vigie",
            path: "Sources/Vigie"
        ),
        .testTarget(
            name: "VigieTests",
            dependencies: ["Vigie"],
            path: "tests/VigieTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
