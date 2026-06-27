import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Persists full images and thumbnails to disk, keeping the database lean.
public final class ImageStore: @unchecked Sendable {
    private let imagesDir: URL
    private let thumbsDir: URL
    private let thumbMaxPixels: CGFloat

    public struct SavedImage: Sendable {
        public let imagePath: String
        public let thumbPath: String
        public let width: Int
        public let height: Int
        public let byteSize: Int
    }

    public init(imagesDir: URL = AppPaths.imagesDirectory,
                thumbsDir: URL = AppPaths.thumbsDirectory,
                thumbMaxPixels: CGFloat = 320) {
        self.imagesDir = imagesDir
        self.thumbsDir = thumbsDir
        self.thumbMaxPixels = thumbMaxPixels
    }

    /// Writes `data` (PNG/TIFF/etc.) as a PNG plus a JPEG thumbnail. Returns paths + dimensions.
    public func save(imageData data: Data, id: String = UUID().uuidString) throws -> SavedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SQLiteError.message("Unreadable image data")
        }

        let imageURL = imagesDir.appendingPathComponent("\(id).png")
        let thumbURL = thumbsDir.appendingPathComponent("\(id).jpg")

        // Full image as PNG.
        try writePNG(cgImage, to: imageURL)

        // Thumbnail via ImageIO (downsampled, cheap).
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbMaxPixels
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            try writeJPEG(thumb, to: thumbURL, quality: 0.8)
        } else {
            try writeJPEG(cgImage, to: thumbURL, quality: 0.8)
        }

        let onDiskSize = (try? FileManager.default.attributesOfItem(atPath: imageURL.path))?[.size] as? Int
        return SavedImage(
            imagePath: imageURL.path,
            thumbPath: thumbURL.path,
            width: cgImage.width,
            height: cgImage.height,
            byteSize: onDiskSize ?? data.count
        )
    }

    /// Removes any of the given files that exist (used after deletes/pruning).
    public func deleteFiles(_ paths: [String]) {
        for p in paths where !p.isEmpty {
            try? FileManager.default.removeItem(atPath: p)
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SQLiteError.message("Could not create PNG destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw SQLiteError.message("Could not write PNG")
        }
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw SQLiteError.message("Could not create JPEG destination")
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            throw SQLiteError.message("Could not write JPEG")
        }
    }
}
