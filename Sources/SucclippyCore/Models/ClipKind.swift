import Foundation

/// The category of a clipboard entry. Drives icons, preview rendering and available actions.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case image
    case file
    case link
    case color

    /// SF Symbol used as the row/preview glyph when no richer thumbnail exists.
    public var symbolName: String {
        switch self {
        case .text:     return "text.alignleft"
        case .richText: return "doc.richtext"
        case .image:    return "photo"
        case .file:     return "doc"
        case .link:     return "link"
        case .color:    return "paintpalette"
        }
    }

    /// Human label used in filter chips and metadata.
    public var displayName: String {
        switch self {
        case .text:     return "Text"
        case .richText: return "Text"
        case .image:    return "Image"
        case .file:     return "File"
        case .link:     return "Link"
        case .color:    return "Color"
        }
    }
}

/// Filter buckets shown above the item list.
public enum ClipFilter: String, CaseIterable, Sendable {
    case all
    case text
    case links
    case images
    case files
    case pinned

    public var title: String {
        switch self {
        case .all:    return "All"
        case .text:   return "Text"
        case .links:  return "Links"
        case .images: return "Images"
        case .files:  return "Files"
        case .pinned: return "Pinned"
        }
    }

    public var symbolName: String {
        switch self {
        case .all:    return "square.grid.2x2"
        case .text:   return "text.alignleft"
        case .links:  return "link"
        case .images: return "photo"
        case .files:  return "doc"
        case .pinned: return "pin"
        }
    }

    /// The `ClipKind`s included by this filter, or `nil` for "all / pinned" which are handled specially.
    public var kinds: [ClipKind]? {
        switch self {
        case .all, .pinned: return nil
        case .text:         return [.text, .richText, .color]
        case .links:        return [.link]
        case .images:       return [.image]
        case .files:        return [.file]
        }
    }
}
