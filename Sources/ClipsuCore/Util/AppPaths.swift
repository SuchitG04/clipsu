import Foundation

/// Centralised on-disk locations under Application Support.
public enum AppPaths {
    public static let appName = "Clipsu"

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    public static var databaseURL: URL {
        supportDirectory.appendingPathComponent("db.sqlite", isDirectory: false)
    }

    public static var imagesDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("images", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    public static var thumbsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("thumbs", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    private static func ensureDirectory(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
