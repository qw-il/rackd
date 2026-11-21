import CoreImage
import UIKit
import Vision

enum BackgroundRemovalError: LocalizedError {
    case invalidImage
    case noSubjectFound
    case renderFailed
    case unavailableInSimulator
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The photo couldn't be read."
        case .noSubjectFound:
            "Couldn't find a clear item in the photo. Try a plain, contrasting background with the whole item in frame."
        case .renderFailed:
            "The cut-out image couldn't be created."
        case .unavailableInSimulator:
            "Subject lifting doesn't run in the iOS Simulator, and this photo's background isn't plain enough for the backup method. Try on a real iPhone."
        case .visionFailed(let message):
            "Background removal failed: \(message)"
        }
    }
}

enum BackgroundRemovalMethod {
    /// Apple's on-device subject lifting (best quality, any background).
    case subjectLifting
    /// Flood-fill of a plain, uniform background (works everywhere, incl. Simulator).
    case plainBackground
}

struct BackgroundRemovalResult {
    let image: UIImage
    let method: BackgroundRemovalMethod
}

/// Removes the background behind a clothing item.
///
/// Tries Vision's subject lifting first (the same tech as "Lift subject from
/// background" in Photos). If that fails – e.g. in the Simulator, or when Vision
/// finds no subject – falls back to removing a plain, uniform background, which
/// handles product shots and clothes photographed on a wall, floor or bed.
enum BackgroundRemover {
    private static let context = CIContext()

    static func removeBackground(from image: UIImage) throws -> BackgroundRemovalResult {
        guard let cgImage = image.standardCGImage() else { throw BackgroundRemovalError.invalidImage }

        let primaryError: Error
        #if targetEnvironment(simulator)
        primaryError = BackgroundRemovalError.unavailableInSimulator
        #else
        do {
            return BackgroundRemovalResult(image: try liftSubject(from: cgImage), method: .subjectLifting)
        } catch {
            primaryError = error
        }
        #endif

        if let cutout = PlainBackgroundRemover.removeBackground(from: cgImage) {
            return BackgroundRemovalResult(image: cutout, method: .plainBackground)
        }
        if let known = primaryError as? BackgroundRemovalError {
            throw known
        }
        throw BackgroundRemovalError.visionFailed(primaryError.localizedDescription)
    }

    private static func liftSubject(from cgImage: CGImage) throws -> UIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noSubjectFound
        }

        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let output = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw BackgroundRemovalError.renderFailed
        }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }
}

/// Removes a plain background by flood-filling from the image edges over
/// pixels close to the dominant border colour. Interior areas that happen to
/// match (e.g. a white logo) are kept because they aren't connected to the edge.
enum PlainBackgroundRemover {
    static func removeBackground(from source: CGImage) -> UIImage? {
        let width = source.width
        let height = source.height
        guard width >= 16, height >= 16 else { return nil }
        let pixelCount = width * height

        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        var alpha = [UInt8](repeating: 255, count: pixelCount)

        let ok: Bool = pixels.withUnsafeMutableBufferPointer { px in
            alpha.withUnsafeMutableBufferPointer { mask in
                computeMask(px: px, mask: mask, width: width, height: height)
            }
        }
        guard ok else { return nil }

        // Apply the mask (premultiplied) and find the subject's bounding box.
        var minX = width, minY = height, maxX = -1, maxY = -1
        pixels.withUnsafeMutableBufferPointer { px in
            alpha.withUnsafeBufferPointer { mask in
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * width + x
                        let a = min(Int(mask[i]), Int(px[i * 4 + 3]))
                        if a == 0 {
                            px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0
                            continue
                        }
                        if a < 255 {
                            let original = Int(px[i * 4 + 3])
                            for c in 0..<3 {
                                px[i * 4 + c] = UInt8(Int(px[i * 4 + c]) * a / max(original, 1))
                            }
                            px[i * 4 + 3] = UInt8(a)
                        }
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            )?.makeImage()
        }
        let margin = 4
        let crop = CGRect(
            x: max(minX - margin, 0),
            y: max(minY - margin, 0),
            width: min(maxX + margin, width - 1) - max(minX - margin, 0) + 1,
            height: min(maxY + margin, height - 1) - max(minY - margin, 0) + 1
        )
        guard let cropped = output?.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// Fills `mask` with 0 for background, 255 for foreground and soft values
    /// along the edge. Returns false if the background isn't plain enough.
    private static func computeMask(
        px: UnsafeMutableBufferPointer<UInt8>,
        mask: UnsafeMutableBufferPointer<UInt8>,
        width: Int,
        height: Int
    ) -> Bool {
        let pixelCount = width * height
        let band = max(2, min(width, height) / 50)

        // 1. Sample the border.
        var rs: [Int] = [], gs: [Int] = [], bs: [Int] = []
        var transparentBorder = 0, borderTotal = 0
        for y in 0..<height {
            let fullRow = y < band || y >= height - band
            var x = 0
            while x < width {
                let i = (y * width + x) * 4
                borderTotal += 1
                if px[i + 3] < 128 {
                    transparentBorder += 1
                } else {
                    rs.append(Int(px[i])); gs.append(Int(px[i + 1])); bs.append(Int(px[i + 2]))
                }
                // Skip the middle of non-border rows.
                x = (!fullRow && x == band - 1) ? width - band : x + 1
            }
        }
        let alreadyTransparent = Double(transparentBorder) / Double(max(borderTotal, 1)) > 0.5

        var bgR = 0, bgG = 0, bgB = 0, tolerance2 = 0
        if !alreadyTransparent {
            guard rs.count > 20 else { return false }
            func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
            bgR = median(rs); bgG = median(gs); bgB = median(bs)

            // 2. Adapt the tolerance to how noisy the background is.
            var distances = (0..<rs.count).map { k -> Int in
                let dr = rs[k] - bgR, dg = gs[k] - bgG, db = bs[k] - bgB
                return dr * dr + dg * dg + db * db
            }
            distances.sort()
            let p75 = Double(distances[distances.count * 3 / 4]).squareRoot()
            let tolerance = min(max(p75 * 2.5, 18), 55)
            tolerance2 = Int(tolerance * tolerance)

            // Background must be mostly one colour, or this method isn't suitable.
            let matching = distances.filter { $0 <= tolerance2 }.count
            guard Double(matching) / Double(distances.count) >= 0.6 else { return false }
        }

        func isBackground(_ p: Int) -> Bool {
            let i = p * 4
            if px[i + 3] < 128 { return true }
            if alreadyTransparent { return false }
            let dr = Int(px[i]) - bgR, dg = Int(px[i + 1]) - bgG, db = Int(px[i + 2]) - bgB
            return dr * dr + dg * dg + db * db <= tolerance2
        }

        // 3. Flood fill from the outer edge.
        var visited = [Bool](repeating: false, count: pixelCount)
        var stack: [Int] = []
        stack.reserveCapacity(4096)
        func seed(_ p: Int) {
            if !visited[p] && isBackground(p) {
                visited[p] = true
                stack.append(p)
            }
        }
        for x in 0..<width {
            seed(x)
            seed((height - 1) * width + x)
        }
        for y in 0..<height {
            seed(y * width)
            seed(y * width + width - 1)
        }
        var backgroundCount = 0
        while let p = stack.popLast() {
            mask[p] = 0
            backgroundCount += 1
            let x = p % width, y = p / width
            if x > 0 { seed(p - 1) }
            if x < width - 1 { seed(p + 1) }
            if y > 0 { seed(p - width) }
            if y < height - 1 { seed(p + width) }
        }

        // 4. Sanity check: something sensible must be left.
        let foregroundFraction = 1 - Double(backgroundCount) / Double(pixelCount)
        guard foregroundFraction > 0.03, foregroundFraction < 0.97 else { return false }

        // 5. Soften the edge: foreground pixels touching background fade a little.
        var softened = [UInt8](repeating: 0, count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let p = y * width + x
                guard mask[p] != 0 else { continue }
                var sum = 0, n = 0
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0, yy < height else { continue }
                    for dx in -1...1 {
                        let xx = x + dx
                        guard xx >= 0, xx < width else { continue }
                        sum += Int(mask[yy * width + xx]); n += 1
                    }
                }
                softened[p] = UInt8(sum / max(n, 1))
            }
        }
        for p in 0..<pixelCount { mask[p] = softened[p] }
        return true
    }
}

extension UIImage {
    /// An 8-bit sRGB, upright CGImage. Vision and our pixel code expect this;
    /// wide-colour (16-bit float) images from the renderer can otherwise fail.
    func standardCGImage() -> CGImage? {
        if let existing = self.cgImage, existing.bitsPerComponent == 8, imageOrientation == .up {
            return existing
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }.cgImage
    }
}
