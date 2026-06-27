// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Succlippy",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure-ish, testable logic: models, SQLite storage, classification, OCR.
        .target(
            name: "SucclippyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // The GUI application: app lifecycle, panel, services that drive AppKit.
        .executableTarget(
            name: "Succlippy",
            dependencies: ["SucclippyCore"]
        ),
        .testTarget(
            name: "SucclippyCoreTests",
            dependencies: ["SucclippyCore"]
        ),
    ]
)
