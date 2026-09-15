import PhotosUI
import SpliitAPI
import SpliitCore
import SwiftUI
import VisionKit

/// The receipts kept with an expense: a grid of what is attached, and a way to add more.
///
/// The uploading itself is the form's — see `DocumentUploads` for why — and this section draws
/// it: the stored documents, the ones still on their way, and the tile that adds another.
struct ExpenseDocumentsSection: View {

    @Environment(AppModel.self) private var app

    @Binding var documents: [ExpenseDocument]

    /// What is being uploaded, and the pictures of what has been.
    let uploads: DocumentUploads

    /// The instance the expense's group is on. Documents go to the bucket that instance signs
    /// for, and whether it has one at all is answered per instance.
    let instanceURL: URL

    @State private var presented: Presented?
    @State private var isShowingLibrary = false
    @State private var pickedItems: [PhotosPickerItem] = []

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
                    DocumentThumbnail(document: document, images: uploads.images)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Document \(index + 1)"))
                .accessibilityIdentifier(AccessibilityID.Documents.thumbnail(index))
            }

            ForEach(uploads.inFlight) { upload in
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

            if app.storesDocuments(on: instanceURL) {
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
                DocumentGalleryView(documents: $documents, images: uploads.images, startingAt: id)
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
        switch uploads.status {
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
            let data = try? await item.loadTransferable(type: Data.self)
            uploads.attach(file: data, to: instanceURL, app: app) { documents.append($0) }
        }
        pickedItems = []
    }

    private func attach(_ photo: ReceiptPhoto) {
        uploads.attach(photo, to: instanceURL, app: app) { documents.append($0) }
    }
}
