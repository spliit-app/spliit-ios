import CoreGraphics
import ImageIO
import SwiftUI
import VisionKit

/// A photograph of a receipt, in the form Vision wants it.
///
/// A `CGImage` and an orientation rather than the `UIImage` it came from: the two are `Sendable`,
/// so the scan runs off the main actor without the picture having to be copied first — and a
/// photo out of the library is very often sideways, which is the difference between a transcript
/// and a page of nonsense.
struct ReceiptPhoto: Sendable {
    let image: CGImage
    let orientation: CGImagePropertyOrientation

    init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.image = image
        self.orientation = orientation
    }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(image: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }
}

extension CGImagePropertyOrientation {
    /// UIKit and ImageIO number the same eight orientations differently, and nothing converts
    /// between them for you.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The document scanner as something to present, which closes itself when it is finished.
///
/// The dismissal belongs in here rather than in the caller's `isPresented` binding. Writing that
/// binding from the scanner's delegate means two things can close the cover — the binding and
/// SwiftUI's own dismissal of it — and a dismissal that arrives once too often lands on whatever
/// is presented next.
struct DocumentCameraSheet: View {

    @Environment(\.dismiss) private var dismiss
    let onFinish: (ReceiptPhoto?) -> Void

    var body: some View {
        DocumentCamera { photo in
            dismiss()
            onFinish(photo)
        }
        .ignoresSafeArea()
    }
}

/// The system's document scanner, which finds the receipt's edges, straightens it and drops the
/// table it was lying on.
///
/// Worth the wrapper over a plain camera: the crop and the perspective correction are most of
/// what makes the difference between text recognition working and not, and none of it is code
/// this app would want to own.
struct DocumentCamera: UIViewControllerRepresentable {

    /// The first page, or nil if the scan was cancelled or gave nothing back.
    let onFinish: (ReceiptPhoto?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: (ReceiptPhoto?) -> Void

        init(onFinish: @escaping (ReceiptPhoto?) -> Void) {
            self.onFinish = onFinish
        }

        // One receipt is one page. Someone who scans several gets the first, which is the one
        // they framed first — and an expense has one amount however many pages were captured.
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            onFinish(scan.pageCount > 0 ? ReceiptPhoto(scan.imageOfPage(at: 0)) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            onFinish(nil)
        }
    }
}
