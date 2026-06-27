import Foundation

/// Pure, unit-testable helpers for classifying copied text.
public enum ContentClassifier {
    private static let linkSchemes: Set<String> = ["http", "https", "ftp", "ftps", "mailto", "file"]

    /// True when the whole trimmed string is a single URL.
    public static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else {
            return false
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           linkSchemes.contains(scheme), url.host != nil || scheme == "mailto" || scheme == "file" {
            return true
        }
        // Bare domains like "www.apple.com" or "apple.com/path".
        if trimmed.lowercased().hasPrefix("www.") { return true }
        return false
    }

    /// Matches `#RGB`, `#RRGGBB`, `#RRGGBBAA` (case-insensitive).
    public static func isHexColor(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return false }
        let hex = t.dropFirst()
        guard [3, 6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    /// Determines the kind of a plain-text payload.
    public static func kind(forPlainText text: String) -> ClipKind {
        if isHexColor(text) { return .color }
        if isLink(text) { return .link }
        return .text
    }

    /// Normalises a URL string so "apple.com" and "www.apple.com" can be opened in a browser.
    public static func openableURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if trimmed.lowercased().hasPrefix("www.") { return URL(string: "https://\(trimmed)") }
        return nil
    }
}
