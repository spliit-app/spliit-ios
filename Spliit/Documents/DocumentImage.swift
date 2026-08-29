import ImageIO
import UIKit

/// A picture on its way to the instance's bucket: the bytes to upload, and the size that gets
/// stored beside them.
///
/// The web app refuses a file over 5 MB and uploads whatever else it is handed. A phone cannot
/// work that way — a camera produces 3 to 12 MB routinely, and someone who has just photographed
/// a receipt would only be told to go and find a smaller one. So the picture is re-encoded to fit
/// rather than rejected, which is also how it comes to be a JPEG whatever it arrived as.
struct DocumentImage: Sendable {
    let data: Data
    /// Pixels. This is what `ExpenseDocument` records and what the web app lays its gallery out
    /// with, and it is measured after the redraw, so it describes the file rather than the
    /// original.
    let width: Int
    let height: Int

    var contentType: String { "image/jpeg" }
}

extension DocumentImage {

    /// Big enough to read the small print on a till receipt, and about a tenth of the pixels a
    /// modern camera produces.
    nonisolated private static let longestSide: CGFloat = 2048

    /// The web app's ceiling, kept so a document attached from either product is the same kind of
    /// thing. Nothing here comes near it: 2048px of receipt lands around 400 KB.
    nonisolated private static let maximumBytes = 5 * 1024 * 1024

    /// Redraws a photograph as something worth uploading, or nil if it cannot be encoded at all.
    ///
    /// Takes a `ReceiptPhoto` — a `CGImage` and an orientation — for the reason that type exists:
    /// both halves are `Sendable`, so this runs off the main actor and a 12-megapixel JPEG encode
    /// doesn't stutter the form somebody is filling in.
    ///
    /// The redraw is not only about size. It bakes in the orientation, without which a photo out
    /// of the library uploads sideways and the width and height stored beside it describe it the
    /// wrong way round; and it drops every other EXIF field along with it, including where the
    /// photo was taken. A receipt has no business carrying somebody's location into a bucket.
    nonisolated static func prepared(from photo: ReceiptPhoto) -> DocumentImage? {
        let source = UIImage(
            cgImage: photo.image,
            scale: 1,
            orientation: UIImage.Orientation(photo.orientation)
        )
        var candidate = scaled(source, longestSideAtMost: longestSide)

        // Three qualities at each of three sizes. In practice the first attempt is the one that
        // returns; the rest are there so an enormous photograph cannot get through unshrunk.
        for _ in 0..<3 {
            for quality in [0.8, 0.55, 0.35] as [CGFloat] {
                guard let data = candidate.jpegData(compressionQuality: quality) else {
                    return nil
                }
                if data.count <= maximumBytes {
                    return DocumentImage(
                        data: data,
                        width: Int(candidate.size.width),
                        height: Int(candidate.size.height)
                    )
                }
            }
            candidate = scaled(
                candidate,
                longestSideAtMost: max(candidate.size.width, candidate.size.height) / 2
            )
        }
        return nil
    }

    /// Draws the image at a scale of 1, so its size in points is its size in pixels — which is
    /// what makes `width` and `height` mean what the server takes them to mean.
    nonisolated private static func scaled(
        _ image: UIImage, longestSideAtMost side: CGFloat
    ) -> UIImage {
        let pixels = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longest = max(pixels.width, pixels.height)
        let factor = longest > side && longest > 0 ? side / longest : 1
        let target = CGSize(
            width: max(1, (pixels.width * factor).rounded()),
            height: max(1, (pixels.height * factor).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // A receipt is a rectangle of paper with no transparency worth keeping, and an opaque
        // context is what stops the JPEG encoder turning an alpha channel into a black edge.
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension UIImage.Orientation {
    /// The other direction from the conversion in `ReceiptPhoto.swift`: the same eight
    /// orientations, numbered differently by UIKit and by ImageIO, with nothing in the SDK to
    /// convert between them.
    nonisolated init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
