import CoreImage
import UIKit
import Vision

enum BackgroundRemovalError: Error {
    case invalidImage
    case noSubjectFound
    case renderFailed
}

/// Lifts the main subject out of a photo using Vision's on-device subject
/// segmentation (the same tech as "Lift subject from background" in Photos).
enum BackgroundRemover {
    private static let context = CIContext()

    /// Returns a transparent-background image cropped to the subject.
    /// Note: requires a real device; the iOS Simulator can't run this request.
    static func removeBackground(from image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else { throw BackgroundRemovalError.invalidImage }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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
