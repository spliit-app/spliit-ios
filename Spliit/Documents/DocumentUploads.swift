import SpliitAPI
import SwiftUI

/// The documents being added to one expense: the uploads in flight, how the last one went, and
/// the pictures of what has been stored.
///
/// Owned by the form rather than by the section that draws them, and that is the point. A `Form`
/// builds its rows as they scroll into view, and the documents grid sits at the bottom of a long
/// one — so an upload that could only be started from inside the grid waited for somebody to
/// scroll there. The receipt scanner got away with it because a person scanning has the form in
/// front of them; the shortcut that attaches a receipt hands it over before the form has drawn at
/// all, and would have opened it with Save live and nothing uploading. Starting the upload here
/// means the form does it the moment it has somewhere to send the picture, grid or no grid.
///
/// The upload happens before the save, exactly as it does on the web: a document is a URL by the
/// time the form holds one, so what the expense stores is only ever an address. Two things follow,
/// and both are true of the web app as well. An expense that is written and then abandoned leaves
/// an object in the bucket that nothing points at, and removing a document forgets its URL
/// without deleting anything — neither product has credentials for the bucket, only the instance.
@Observable
@MainActor
final class DocumentUploads {

    /// A picture being uploaded. Held so the grid can show it, greyed, in the place it is about
    /// to occupy — an upload with nothing on screen is a spinner beside a form that looks
    /// unchanged.
    ///
    /// A thumbnail rather than the photograph. The original can be twelve megapixels, five of
    /// them can be picked at once, and drawing one into a ninety-point square decodes the whole
    /// thing; nil when even that fails, which costs the tile its picture and nothing else.
    struct Upload: Identifiable {
        let id = UUID()
        let preview: UIImage?
    }

    enum Status: Equatable {
        case idle
        case uploading
        /// This instance keeps no documents. Not an error, and not worth offering to retry.
        case unsupported
        case failed(String)
    }

    private(set) var inFlight: [Upload] = []
    private(set) var status = Status.idle

    /// Shared by the grid and the gallery, so opening a receipt shows the picture the grid
    /// already has.
    let images = DocumentImages()

    /// Whether the form should wait before saving: a document is on the expense only once the
    /// instance has answered with its address, and a save before that writes the expense
    /// without it.
    var isUploading: Bool { !inFlight.isEmpty }

    /// An image file as it arrived out of the photo library — or nil, when the library could not
    /// produce one. Either way, one this device cannot read is reported in the grid's footer,
    /// beside the tile it would have been.
    func attach(
        file data: Data?,
        to instanceURL: URL,
        app: AppModel,
        onStored: @escaping (ExpenseDocument) -> Void
    ) {
        guard let data, let photo = ReceiptPhoto(data: data) else {
            status = .failed(String(localized: "That photo couldn’t be read."))
            return
        }
        attach(photo, to: instanceURL, app: app, onStored: onStored)
    }

    /// Uploads a photograph to the bucket `instanceURL` signs for, and hands back the document
    /// to put on the expense once it has landed.
    func attach(
        _ photo: ReceiptPhoto,
        to instanceURL: URL,
        app: AppModel,
        onStored: @escaping (ExpenseDocument) -> Void
    ) {
        // Already answered for this session: the grid hides its add tile on the same condition,
        // and a photograph that arrives some other way deserves the same answer rather than a
        // request the instance has already refused once.
        guard app.storesDocuments(on: instanceURL) else {
            status = .unsupported
            return
        }

        let full = UIImage(
            cgImage: photo.image, scale: 1, orientation: UIImage.Orientation(photo.orientation)
        )
        let upload = Upload(
            preview: full.preparingThumbnail(of: CGSize(width: 300, height: 300))
        )
        inFlight.append(upload)
        status = .uploading

        Task {
            defer { inFlight.removeAll { $0.id == upload.id } }

            // Off the main actor: re-encoding twelve megapixels is a tenth of a second the form
            // would otherwise spend not responding.
            guard let prepared = await Task.detached(priority: .userInitiated, operation: {
                DocumentImage.prepared(from: photo)
            }).value else {
                status = .failed(String(localized: "That photo couldn’t be read."))
                return
            }

            do {
                let uploader = DocumentUploader(baseURL: instanceURL)
                let url = try await uploader.upload(
                    prepared.data, contentType: prepared.contentType
                )
                // What everyone else will see, rather than the original: the thumbnail is then
                // the picture that was actually stored, and it needs no round trip to appear.
                if let stored = UIImage(data: prepared.data) {
                    images.remember(stored, for: url)
                }
                onStored(
                    ExpenseDocument(
                        id: ExpenseDocument.newID(),
                        url: url,
                        width: prepared.width,
                        height: prepared.height
                    )
                )
                Analytics.shared.event(.attachDocument)
                status = .idle
            } catch DocumentUploader.Failure.unsupported {
                // Remembered for the session, so the next expense doesn't offer an upload this
                // instance has already said it cannot accept.
                app.noteDocumentStorageIsUnavailable(on: instanceURL)
                status = .unsupported
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
