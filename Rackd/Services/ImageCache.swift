import UIKit

/// Decoding PNG data on every SwiftUI render is slow; cache decoded images per item.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for item: ClothingItem) -> UIImage? {
        let key = cacheKey(for: item)
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: item.imageData) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private func cacheKey(for item: ClothingItem) -> NSString {
        // Reading imageVersion also makes SwiftUI re-render when the image changes.
        "\(item.id.uuidString)-\(item.imageVersion)" as NSString
    }
}

extension UIImage {
    /// PNG keeps the transparent background of cut-outs.
    func pngDataForStorage() -> Data {
        pngData() ?? jpegData(compressionQuality: 0.85) ?? Data()
    }
}
