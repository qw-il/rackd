import Foundation
import SwiftData

@Model
final class ClothingItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ClothingCategory.tops.rawValue
    /// PNG of the item with its background removed (or the original photo if removal failed).
    @Attribute(.externalStorage) var imageData: Data = Data()
    /// The photo as it was taken, kept so background removal can be re-run.
    @Attribute(.externalStorage) var originalImageData: Data?
    /// Bumped whenever `imageData` is replaced so views and caches refresh
    /// without having to load the (externally stored) image bytes.
    var imageVersion: Int = 0
    var colorName: String = ""
    var colorHex: String = ""
    var brand: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    @Relationship(inverse: \Outfit.items) var outfits: [Outfit] = []

    init(
        name: String,
        category: ClothingCategory,
        imageData: Data,
        originalImageData: Data? = nil,
        colorName: String = "",
        colorHex: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.imageData = imageData
        self.originalImageData = originalImageData
        self.colorName = colorName
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    func replaceImage(with data: Data) {
        imageData = data
        imageVersion += 1
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRaw) ?? .tops }
        set { categoryRaw = newValue.rawValue }
    }

    /// Calendar entries (past or today) that include this item.
    var wornDates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return outfits
            .flatMap(\.plans)
            .map(\.date)
            .filter { $0 <= today }
            .sorted()
    }
}
