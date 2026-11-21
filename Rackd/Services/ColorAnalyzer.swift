import UIKit

struct DetectedColor {
    var name: String
    var hex: String
}

/// Finds the dominant colour of an item, ignoring transparent (removed) background.
enum ColorAnalyzer {
    private static let palette: [(name: String, r: Double, g: Double, b: Double)] = [
        ("Black", 20, 20, 22),
        ("Charcoal", 60, 62, 66),
        ("Gray", 128, 128, 130),
        ("Light Gray", 196, 196, 198),
        ("White", 245, 245, 243),
        ("Cream", 240, 230, 205),
        ("Beige", 210, 190, 160),
        ("Tan", 190, 150, 105),
        ("Brown", 115, 75, 45),
        ("Burgundy", 120, 25, 40),
        ("Red", 200, 35, 40),
        ("Pink", 235, 150, 170),
        ("Orange", 235, 125, 40),
        ("Mustard", 205, 165, 45),
        ("Yellow", 245, 215, 60),
        ("Olive", 110, 115, 55),
        ("Green", 50, 135, 70),
        ("Mint", 165, 220, 190),
        ("Teal", 30, 125, 130),
        ("Light Blue", 150, 190, 230),
        ("Denim", 75, 105, 145),
        ("Blue", 40, 85, 185),
        ("Navy", 30, 40, 80),
        ("Purple", 110, 60, 145),
        ("Lavender", 190, 170, 220),
    ]

    static func dominantColor(of image: UIImage) -> DetectedColor? {
        guard let cgImage = image.cgImage else { return nil }

        // Downsample to a tiny RGBA bitmap.
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drewImage: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drewImage else { return nil }

        // Bucket opaque pixels (4 bits per channel) and pick the most common bucket.
        struct Bucket { var count = 0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3])
            guard alpha > 200 else { continue }
            // Un-premultiply.
            let r = Double(pixels[i]) * 255 / alpha
            let g = Double(pixels[i + 1]) * 255 / alpha
            let b = Double(pixels[i + 2]) * 255 / alpha
            let key = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.r += r
            bucket.g += g
            bucket.b += b
            buckets[key] = bucket
        }
        guard let top = buckets.values.max(by: { $0.count < $1.count }), top.count > 0 else { return nil }

        let r = top.r / Double(top.count)
        let g = top.g / Double(top.count)
        let b = top.b / Double(top.count)
        let hex = String(format: "#%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
        return DetectedColor(name: nearestName(r: r, g: g, b: b), hex: hex)
    }

    private static func nearestName(r: Double, g: Double, b: Double) -> String {
        // "Redmean" weighted distance – cheap and closer to perception than plain RGB.
        palette.min { lhs, rhs in
            distance(r, g, b, lhs) < distance(r, g, b, rhs)
        }?.name ?? "Multicolor"
    }

    private static func distance(_ r: Double, _ g: Double, _ b: Double,
                                 _ p: (name: String, r: Double, g: Double, b: Double)) -> Double {
        let rMean = (r + p.r) / 2
        let dr = r - p.r, dg = g - p.g, db = b - p.b
        return (2 + rMean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rMean) / 256) * db * db
    }
}
