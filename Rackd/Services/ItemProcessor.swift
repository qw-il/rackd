import UIKit

/// The result of running a photo through the full pipeline.
struct ProcessedItem: Identifiable {
    let id = UUID()
    var original: UIImage
    var cutout: UIImage
    var backgroundRemoved: Bool
    /// Why background removal failed, if it did.
    var backgroundRemovalNote: String?
    var category: ClothingCategory
    var categoryConfidence: Double
    var colorName: String
    var colorHex: String
    var suggestedName: String
}

/// Photo → background removed → categorized → colour detected.
enum ItemProcessor {
    static let maxDimension: CGFloat = 1600

    static func process(_ photo: UIImage) async -> ProcessedItem {
        await Task.detached(priority: .userInitiated) {
            let original = photo.normalized(maxDimension: ItemProcessor.maxDimension)

            var cutout = original
            var removed = false
            var note: String?
            do {
                cutout = try BackgroundRemover.removeBackground(from: original).image
                removed = true
            } catch {
                note = error.localizedDescription
            }

            let classification = ClothingClassifier.classify(removed ? cutout : original)
            let color = ColorAnalyzer.dominantColor(of: cutout)

            let noun = classification.label ?? classification.category.singularName
            let suggestedName = [color?.name, noun].compactMap { $0 }.joined(separator: " ")

            return ProcessedItem(
                original: original,
                cutout: cutout,
                backgroundRemoved: removed,
                backgroundRemovalNote: note,
                category: classification.category,
                categoryConfidence: classification.confidence,
                colorName: color?.name ?? "",
                colorHex: color?.hex ?? "",
                suggestedName: suggestedName
            )
        }.value
    }

    /// Re-runs background removal on a stored original.
    static func removeBackground(_ image: UIImage) async -> Result<UIImage, Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try BackgroundRemover.removeBackground(from: image).image }
        }.value
    }
}

extension UIImage {
    /// Redraws the image upright (fixing EXIF orientation) and scales it down
    /// so its longest side is at most `maxDimension` points.
    func normalized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let factor = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Force 8-bit sRGB: on wide-colour iPhones the default can be 16-bit
        // float, which Vision's subject lifting may reject.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
