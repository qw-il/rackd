import Foundation

/// The buckets a clothing item can be sorted into. Raw values are persisted, so
/// don't rename existing cases.
enum ClothingCategory: String, CaseIterable, Identifiable, Codable {
    case tops
    case bottoms
    case dresses
    case outerwear
    case shoes
    case bags
    case accessories

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tops: "Tops"
        case .bottoms: "Bottoms"
        case .dresses: "Dresses"
        case .outerwear: "Outerwear"
        case .shoes: "Shoes"
        case .bags: "Bags"
        case .accessories: "Accessories"
        }
    }

    var singularName: String {
        switch self {
        case .tops: "Top"
        case .bottoms: "Bottoms"
        case .dresses: "Dress"
        case .outerwear: "Jacket"
        case .shoes: "Shoes"
        case .bags: "Bag"
        case .accessories: "Accessory"
        }
    }

    var symbolName: String {
        switch self {
        case .tops: "tshirt"
        case .bottoms: "figure.walk"
        case .dresses: "figure.dress.line.vertical.figure"
        case .outerwear: "cloud.rain"
        case .shoes: "shoeprints.fill"
        case .bags: "bag"
        case .accessories: "eyeglasses"
        }
    }

    /// Default spot on the outfit canvas, in normalized (0...1) coordinates.
    var defaultCanvasPosition: CGPoint {
        switch self {
        case .outerwear: CGPoint(x: 0.30, y: 0.30)
        case .tops: CGPoint(x: 0.50, y: 0.27)
        case .dresses: CGPoint(x: 0.50, y: 0.42)
        case .bottoms: CGPoint(x: 0.50, y: 0.62)
        case .shoes: CGPoint(x: 0.50, y: 0.88)
        case .bags: CGPoint(x: 0.82, y: 0.58)
        case .accessories: CGPoint(x: 0.82, y: 0.15)
        }
    }

    /// Default width on the outfit canvas, as a fraction of the canvas width.
    var defaultCanvasScale: Double {
        switch self {
        case .outerwear: 0.48
        case .tops: 0.44
        case .dresses: 0.48
        case .bottoms: 0.40
        case .shoes: 0.30
        case .bags: 0.26
        case .accessories: 0.22
        }
    }

    /// Stacking order on the canvas: higher draws on top.
    var defaultZIndex: Int {
        switch self {
        case .bottoms: 0
        case .dresses: 1
        case .tops: 2
        case .outerwear: 3
        case .shoes: 4
        case .bags: 5
        case .accessories: 6
        }
    }
}
