import AppKit
import SwiftUI

/// Tiny path-keyed NSImage cache so scrolling the list doesn't hit disk repeatedly.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(atPath path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// Loads an image from a file path with the shared cache, with a graceful placeholder.
struct CachedImage: View {
    let path: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let path, let nsImage = ImageCache.shared.image(atPath: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Color.primary.opacity(0.05)
                Image(systemName: "photo")
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
