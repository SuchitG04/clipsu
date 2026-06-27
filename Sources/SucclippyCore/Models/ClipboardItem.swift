import Foundation

/// A single stored clipboard entry. Mirrors one row of the `items` table.
///
/// Images are *not* stored inline — `imagePath`/`thumbPath` point at files on disk
/// (see `ImageStore`). Only searchable text + metadata live in the database.
public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: ClipKind

    /// Plain, searchable text for text/link items; a short preview string otherwise.
    public var plainText: String?
    /// Original rich representation (RTF data) when the source provided one, so paste keeps formatting.
    public var richData: Data?
    /// Text recognised inside an image by Vision OCR. `nil` until OCR completes.
    public var ocrText: String?

    public var imagePath: String?
    public var thumbPath: String?
    public var imageWidth: Int?
    public var imageHeight: Int?

    /// File-system paths for file copies (NSFilenamesPboardType).
    public var fileURLs: [String]?

    public var sourceBundleID: String?
    public var sourceAppName: String?

    /// SHA-256 of the canonical content; used for dedup.
    public var contentHash: String
    public var byteSize: Int
    public var pinned: Bool
    public var copyCount: Int
    public var createdAt: Date
    public var lastUsedAt: Date

    public init(
        id: Int64 = 0,
        kind: ClipKind,
        plainText: String? = nil,
        richData: Data? = nil,
        ocrText: String? = nil,
        imagePath: String? = nil,
        thumbPath: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        fileURLs: [String]? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        byteSize: Int,
        pinned: Bool = false,
        copyCount: Int = 1,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.richData = richData
        self.ocrText = ocrText
        self.imagePath = imagePath
        self.thumbPath = thumbPath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.pinned = pinned
        self.copyCount = copyCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// A single-line title for the list row.
    public var displayTitle: String {
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image · \(w)×\(h)" }
            return "Image"
        case .file:
            if let urls = fileURLs, !urls.isEmpty {
                let names = urls.map { ($0 as NSString).lastPathComponent }
                return names.count == 1 ? names[0] : "\(names[0]) +\(names.count - 1)"
            }
            return "File"
        default:
            let raw = (plainText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let collapsed = raw.replacingOccurrences(of: "\n", with: " ")
            return collapsed.isEmpty ? kind.displayName : collapsed
        }
    }
}
