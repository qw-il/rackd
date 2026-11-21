import Foundation
import SwiftData

/// Where an item sits on the outfit canvas. Coordinates are normalized to the
/// canvas size so outfits render the same at any size.
struct OutfitPlacement: Codable, Hashable, Identifiable {
    var itemID: UUID
    var x: Double
    var y: Double
    /// Item width as a fraction of canvas width.
    var scale: Double
    var zIndex: Int

    var id: UUID { itemID }

    static func `default`(for item: ClothingItem) -> OutfitPlacement {
        let category = item.category
        return OutfitPlacement(
            itemID: item.id,
            x: category.defaultCanvasPosition.x,
            y: category.defaultCanvasPosition.y,
            scale: category.defaultCanvasScale,
            zIndex: category.defaultZIndex
        )
    }
}

/// A placement paired with the item it places.
struct CanvasEntry: Identifiable {
    var placement: OutfitPlacement
    var item: ClothingItem
    var id: UUID { placement.itemID }
}

@Model
final class Outfit {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var items: [ClothingItem] = []
    /// JSON-encoded `[OutfitPlacement]`.
    var layoutData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \OutfitPlan.outfit) var plans: [OutfitPlan] = []

    init(name: String, items: [ClothingItem], placements: [OutfitPlacement]) {
        self.id = UUID()
        self.name = name
        self.items = items
        self.createdAt = Date()
        self.placements = placements
    }

    var placements: [OutfitPlacement] {
        get { (try? JSONDecoder().decode([OutfitPlacement].self, from: layoutData)) ?? [] }
        set { layoutData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Placements paired with their items, dropping any whose item was deleted,
    /// and adding defaults for items that have no stored placement.
    var resolvedPlacements: [CanvasEntry] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [CanvasEntry] = []
        var seen = Set<UUID>()
        for placement in placements {
            if let item = byID[placement.itemID], !seen.contains(item.id) {
                result.append(CanvasEntry(placement: placement, item: item))
                seen.insert(item.id)
            }
        }
        for item in items where !seen.contains(item.id) {
            result.append(CanvasEntry(placement: .default(for: item), item: item))
        }
        return result.sorted { $0.placement.zIndex < $1.placement.zIndex }
    }

    var displayName: String {
        name.isEmpty ? "Untitled Outfit" : name
    }
}
