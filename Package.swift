// swift-tools-version:5.9
import PackageDescription

// `swift run iAnishFirewall` for development; ./build.sh produces the .app bundle.
let package = Package(
    name: "iAnishFirewall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iAnishFirewall",
            path: "Sources",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
