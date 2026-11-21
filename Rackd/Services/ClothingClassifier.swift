import UIKit
import Vision

struct ClassificationResult {
    var category: ClothingCategory
    /// 0...1 – how sure we are. Low values mean we fell back to a guess.
    var confidence: Double
    /// Best human-readable label, e.g. "Jeans" or "Sneaker".
    var label: String?
}

/// Sorts a clothing photo into a `ClothingCategory` using Vision's built-in
/// on-device image classifier, with a shape-based fallback.
enum ClothingClassifier {
    /// Keywords (matched against whole words of Vision's labels) for each category.
    /// Order matters a little: more specific categories are checked first on ties.
    private static let keywords: [(ClothingCategory, Set<String>)] = [
        (.shoes, ["shoe", "shoes", "sneaker", "sneakers", "boot", "boots", "sandal", "sandals",
                  "heel", "heels", "footwear", "loafer", "loafers", "slipper", "slippers",
                  "clog", "clogs", "flipflop", "moccasin", "pump", "pumps", "cleat", "cleats"]),
        (.bags, ["bag", "bags", "handbag", "purse", "backpack", "tote", "satchel", "clutch",
                 "luggage", "briefcase", "wallet", "duffel"]),
        (.dresses, ["dress", "dresses", "gown", "sundress", "jumpsuit", "romper", "kimono", "sari"]),
        (.outerwear, ["coat", "jacket", "parka", "blazer", "raincoat", "overcoat", "trenchcoat",
                      "windbreaker", "vest", "poncho", "cape", "outerwear", "anorak", "suit"]),
        (.bottoms, ["jeans", "denim", "pants", "trousers", "shorts", "skirt", "leggings",
                    "sweatpants", "chinos", "trouser", "joggers", "slacks"]),
        (.tops, ["shirt", "tshirt", "blouse", "sweater", "hoodie", "sweatshirt", "jersey",
                 "polo", "cardigan", "tank", "turtleneck", "pullover", "top", "camisole", "tunic"]),
        (.accessories, ["hat", "cap", "beanie", "scarf", "glove", "gloves", "sunglasses",
                        "glasses", "eyewear", "belt", "tie", "necktie", "bowtie", "watch",
                        "jewelry", "necklace", "bracelet", "earring", "earrings", "ring",
                        "headband", "bandana", "sock", "socks", "umbrella", "helmet"]),
    ]

    static func classify(_ image: UIImage) -> ClassificationResult {
        guard let cgImage = image.cgImage else { return fallback(for: image) }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return fallback(for: image)
        }

        let observations = (request.results ?? []).filter { $0.confidence > 0.02 }
        var scores: [ClothingCategory: Double] = [:]
        var bestLabel: [ClothingCategory: (String, Double)] = [:]

        for observation in observations {
            let words = tokens(in: observation.identifier)
            for (category, categoryWords) in keywords where !words.isDisjoint(with: categoryWords) {
                let confidence = Double(observation.confidence)
                scores[category, default: 0] += confidence
                if confidence > (bestLabel[category]?.1 ?? 0) {
                    bestLabel[category] = (prettify(observation.identifier), confidence)
                }
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0.05 else {
            return fallback(for: image)
        }
        // Share of the clothing signal this category got, damped when the signal is weak overall.
        let total = scores.values.reduce(0, +)
        let share = best.value / max(total, 0.0001)
        return ClassificationResult(
            category: best.key,
            confidence: share * min(1, best.value * 2),
            label: bestLabel[best.key]?.0
        )
    }

    /// Category implied by free text such as "denim jacket" or "running shoes",
    /// or `nil` if the text doesn't mention a known garment.
    static func category(fromText text: String) -> ClothingCategory? {
        let words = tokens(in: text)
        var best: (category: ClothingCategory, hits: Int)?
        for (category, categoryWords) in keywords {
            let hits = words.intersection(categoryWords).count
            if hits > (best?.hits ?? 0) { best = (category, hits) }
        }
        return best?.category
    }

    /// When the classifier has nothing useful, guess from the subject's shape:
    /// wide & short → shoes, tall & narrow → bottoms/dress, otherwise a top.
    private static func fallback(for image: UIImage) -> ClassificationResult {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return ClassificationResult(category: .tops, confidence: 0, label: nil)
        }
        let aspect = size.height / size.width
        let category: ClothingCategory
        switch aspect {
        case ..<0.75: category = .shoes
        case 1.6...: category = .bottoms
        default: category = .tops
        }
        return ClassificationResult(category: category, confidence: 0.15, label: nil)
    }

    private static func tokens(in identifier: String) -> Set<String> {
        let parts = identifier
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        // Also add the joined form so "t_shirt" matches "tshirt".
        return Set(parts + [parts.joined()])
    }

    private static func prettify(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
