// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipsu",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure-ish, testable logic: models, SQLite storage, classification, OCR.
        .target(
            name: "ClipsuCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // The GUI application: app lifecycle, panel, services that drive AppKit.
        .executableTarget(
            name: "Clipsu",
            dependencies: ["ClipsuCore"]
        ),
        .testTarget(
            name: "ClipsuCoreTests",
            dependencies: ["ClipsuCore"]
        ),
    ]
)
