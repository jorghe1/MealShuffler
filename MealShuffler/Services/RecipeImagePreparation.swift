import UIKit
import ImageIO

enum RecipeImagePreparation {
    /// Redraws in display orientation and emits a supported format with a bounded size.
    static func prepare(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw RecipeImportError.unreadableImage
        }
        if data.count <= 2_000_000, image.imageOrientation == .up,
           max(image.size.width * image.scale, image.size.height * image.scale) <= 1800,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetType(source) as String? == "public.jpeg" { return data }
        let ratio = min(1, 1800 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let result = normalized.jpegData(compressionQuality: 0.75), result.count <= 2_000_000 else {
            throw RecipeImportError.unreadableImage
        }
        return result
    }

    static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
