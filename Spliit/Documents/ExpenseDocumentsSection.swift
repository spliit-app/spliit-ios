import PhotosUI
import SpliitAPI
import SpliitCore
import SwiftUI
import VisionKit

/// The receipts kept with an expense: a grid of what is attached, and a way to add more.
///
/// The upload happens here rather than at save time, exactly as it does on the web: a document is
/// a URL by the time the form holds one, so what the expense stores is only ever an address. Two
/// things follow from that, and both are true of the web app as well. An expense that is written
/// and then abandoned leaves an object in the bucket that nothing points at, and removing a
/// document forgets its URL without deleting anything — neither product has credentials for the
/// bucket, only the instance does.
struct ExpenseDocumentsSection: View {

    @Environment(AppModel.self) private var app

    @Binding var documents: [ExpenseDocument]

    /// Shared with the gallery, so opening a receipt shows the picture the grid already has.
    @State private var images = DocumentImages()
    @State private var uploads: [Upload] = []
    @State private var status = Status.idle
    @State private var presented: Presented?
    @State private var isShowingLibrary = false
    @State private var pickedItems: [PhotosPickerItem] = []

    /// A picture being uploaded. Held so the grid can show it, greyed, in the place it is about
    /// to occupy — an upload with nothing on screen is a spinner beside a form that looks
    /// unchanged.
    ///
    /// A thumbnail rather than the photograph. The original can be twelve megapixels, five of
    /// them can be picked at once, and drawing one into a ninety-point square decodes the whole
    /// thing; nil when even that fails, which costs the tile its picture and nothing else.
    private struct Upload: Identifiable {
        let id = UUID()
        let preview: UIImage?
    }

    private enum Status: Equatable {
        case idle
        case uploading
        /// This instance keeps no documents. Not an error, and not worth offering to retry.
        case unsupported
        case failed(String)
    }

    /// One presentation for the whole section, rather than a `fullScreenCover` per thing to
    /// present. Two of them on one view is a coin toss over which gets shown, and the modifier
    /// stays on a view that never changes identity — see the note in `ReceiptScanSection`.
    private enum Presented: Identifiable, Hashable {
        case camera
        case document(ExpenseDocument.ID)

        var id: Self { self }
    }

    var body: some View {
        Section {
            grid
        } header: {
            Text("Attach documents")
        } footer: {
            footer.accessibilityIdentifier(AccessibilityID.Documents.status)
        }
    }

    // MARK: - The grid

    /// Three columns, which is where the web app's grid ends up too. Fixed rather than adaptive
    /// so a tile's size follows the row's width rather than a minimum measured against it.
    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                Button {
                    presented = .document(document.id)
                } label: {
                    DocumentThumbnail(document: document, images: images)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Document \(index + 1)"))
                .accessibilityIdentifier(AccessibilityID.Documents.thumbnail(index))
            }

            ForEach(uploads) { upload in
                Color(.secondarySystemFill)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let preview = upload.preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .opacity(0.4)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay { ProgressView() }
                    .accessibilityLabel(Text("Uploading"))
            }

            if app.storesDocuments {
                addTile
            }
        }
        .padding(.vertical, 4)
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $pickedItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .task(id: pickedItems.count) { await attachPickedPhotos() }
        .fullScreenCover(item: $presented) { presented in
            switch presented {
            case .camera:
                DocumentCameraSheet { photo in
                    if let photo { attach(photo) }
                }
            case .document(let id):
                DocumentGalleryView(documents: $documents, images: images, startingAt: id)
            }
        }
    }

    /// The tile that adds one. A menu where there is a camera to choose between, a plain button
    /// where there is not — the same shape, and for the same reason, as the scan row above it.
    @ViewBuilder
    private var addTile: some View {
        if offersCamera {
            Menu {
                Button("Take Photo", systemImage: "camera") { presented = .camera }
                Button("Choose Photos", systemImage: "photo.on.rectangle") {
                    isShowingLibrary = true
                }
            } label: {
                addLabel
            }
            .accessibilityLabel(Text("Attach a document"))
            .accessibilityIdentifier(AccessibilityID.Documents.addButton)
        } else {
            Button { pickPhoto() } label: { addLabel }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Attach a document"))
                .accessibilityIdentifier(AccessibilityID.Documents.addButton)
        }
    }

    private var addLabel: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
    }

    /// A `Text` rather than a key, so the one case carrying a message from somewhere else can
    /// show it verbatim instead of becoming a catalogue entry that reads "%@".
    private var footer: Text {
        switch status {
        case .idle:
            documents.isEmpty
                ? Text("Photograph the receipt and it stays with the expense.")
                : Text("Tap a document to see it full size.")
        case .uploading:
            Text("Uploading…")
        case .unsupported:
            // Storing documents needs a bucket the instance's administrator has to configure,
            // and plenty of self-hosted instances have none. Saying so is the whole of what this
            // app can do about it.
            Text("This Spliit instance isn’t set up to store documents.")
        case .failed(let reason):
            Text(reason)
        }
    }

    // MARK: - Picking

    /// Whether there is a camera to choose between. A simulator claims one it hasn't got, and it
    /// has no photo library worth driving either, so under UI test the tile is the single button
    /// that attaches the receipt the app draws for itself.
    private var offersCamera: Bool {
        #if DEBUG
        if UITestSupport.usesSampleReceipt { return false }
        #endif
        return VNDocumentCameraViewController.isSupported
    }

    private func pickPhoto() {
        #if DEBUG
        if let sample = UITestSupport.sampleReceipt() {
            attach(sample)
            return
        }
        #endif
        isShowingLibrary = true
    }

    /// Watched by count rather than by the array: `PhotosPickerItem` is not `Equatable`, and the
    /// count changing is exactly the event worth reacting to.
    ///
    /// The selection is emptied at the end and not at the start, which is not tidiness. Emptying
    /// it changes the very id this task is keyed on, and `task(id:)` answers that by cancelling
    /// what is running — so clearing first would cancel the load of the first photo before it had
    /// finished. Uploading is a `Task` of its own for the same reason: it has to outlive this one.
    private func attachPickedPhotos() async {
        guard !pickedItems.isEmpty else { return }

        for item in pickedItems {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let photo = ReceiptPhoto(image)
            else {
                status = .failed(String(localized: "That photo couldn’t be read."))
                continue
            }
            attach(photo)
        }
        pickedItems = []
    }

    // MARK: - Uploading

    private func attach(_ photo: ReceiptPhoto) {
        let full = UIImage(
            cgImage: photo.image, scale: 1, orientation: UIImage.Orientation(photo.orientation)
        )
        let upload = Upload(
            preview: full.preparingThumbnail(of: CGSize(width: 300, height: 300))
        )
        uploads.append(upload)
        status = .uploading

        Task {
            defer { uploads.removeAll { $0.id == upload.id } }

            // Off the main actor: re-encoding twelve megapixels is a tenth of a second the form
            // would otherwise spend not responding.
            guard let prepared = await Task.detached(priority: .userInitiated, operation: {
                DocumentImage.prepared(from: photo)
            }).value else {
                status = .failed(String(localized: "That photo couldn’t be read."))
                return
            }

            do {
                let uploader = DocumentUploader(baseURL: app.settings.baseURL)
                let url = try await uploader.upload(
                    prepared.data, contentType: prepared.contentType
                )
                // What everyone else will see, rather than the original: the thumbnail is then
                // the picture that was actually stored, and it needs no round trip to appear.
                if let stored = UIImage(data: prepared.data) {
                    images.remember(stored, for: url)
                }
                documents.append(
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
                app.noteDocumentStorageIsUnavailable()
                status = .unsupported
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
