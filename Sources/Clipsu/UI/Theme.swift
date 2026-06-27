import SwiftUI

/// Shared visual constants so the app stays consistent and easy to retune.
enum Theme {
    static let panelWidth: CGFloat = 760
    static let panelHeight: CGFloat = 460
    static let corner: CGFloat = 14
    static let rowCorner: CGFloat = 8
    static let listWidth: CGFloat = 300

    static let rowHeight: CGFloat = 46
    static let hPad: CGFloat = 12
    static let vPad: CGFloat = 8

    /// Subtle separators that read well on a vibrant background.
    static let hairline = Color.primary.opacity(0.08)
    static let secondaryText = Color.primary.opacity(0.55)
    static let tertiaryText = Color.primary.opacity(0.4)
}

extension Date {
    /// Compact, relative-ish stamp for list rows ("2m", "3h", "Apr 5").
    var clipShort: String {
        let now = Date()
        let delta = now.timeIntervalSince(self)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        if delta < 7 * 86_400 { return "\(Int(delta / 86_400))d" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: self)
    }

    var clipLong: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: self)
    }
}

extension Int {
    /// Human byte size ("12 KB", "3.4 MB").
    var clipBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
