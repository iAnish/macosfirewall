// swift-tools-version:5.9
import PackageDescription

// `swift run ScaleneFirewall` for development; ./build.sh produces the .app bundle.
let package = Package(
    name: "ScaleneFirewall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScaleneFirewall",
            path: "Sources",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
