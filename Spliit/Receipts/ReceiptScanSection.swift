import PhotosUI
import SpliitAPI
import SpliitCore
import SwiftUI
import VisionKit

/// The row at the top of a new expense that fills the rest of it in from a photo of the receipt.
///
/// It lives in the form rather than beside the "add expense" button, and the form is its own
/// preview: the web app scans a receipt behind a dialog that shows what it found and then hands
/// those four values to a form that shows them again. Here they land in the fields directly,
/// where they can be corrected in place instead of accepted and then corrected.
///
/// The photo itself is deliberately not kept. Attaching receipts to expenses is a feature of its
/// own — the web app uploads them to S3 — and a thumbnail on this screen would promise the expense
/// keeps a copy when it does not.
struct ReceiptScanSection: View {

    let categories: [ExpenseCategory]
    /// Called with whatever the scan found, on the main actor, for the form to apply.
    let onScan: (ReceiptScan) -> Void

    @State private var phase = Phase.idle
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var pickedItem: PhotosPickerItem?

    private enum Phase: Equatable {
        case idle
        case scanning
        /// A photo that was read. `found` is false when it was read and said nothing.
        case scanned(found: Bool)
        case failed
    }

    var body: some View {
        Section {
            // The presentations hang off the row, and the row keeps one identity for the whole
            // life of the screen — `phase` changes what it says and whether it is enabled, never
            // which view it is.
            //
            // This is load-bearing, and it cost a bug on a real phone. Swapping the row between a
            // menu and a progress indicator rebuilt the view owning `fullScreenCover` in the same
            // update that dismissed it, and the stranded dismissal then landed on the *next*
            // presentation: photograph a receipt, open the camera again, and it closed itself
            // immediately. A simulator has no camera, so nothing in the suite ever presented it.
            scanRow
                .fullScreenCover(isPresented: $isShowingCamera) {
                    DocumentCameraSheet { photo in
                        if let photo { scan(photo) }
                    }
                }
                .photosPicker(
                    isPresented: $isShowingLibrary, selection: $pickedItem, matching: .images
                )
                .task(id: pickedItem) { await loadPickedPhoto() }
        } footer: {
            Text(status)
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.scanStatus)
        }
    }

    @ViewBuilder
    private var scanRow: some View {
        if offersCamera {
            // No identifiers on the two items: an identifier on the `Menu` would stamp them both
            // anyway, and nothing looks for them — the suite reaches the scan through the button
            // below, since a simulator has neither camera nor library.
            Menu {
                Button("Take Photo", systemImage: "camera") { isShowingCamera = true }
                Button("Choose Photo", systemImage: "photo.on.rectangle") {
                    isShowingLibrary = true
                }
            } label: {
                scanLabel
            }
            .disabled(phase == .scanning)
            .accessibilityIdentifier(AccessibilityID.ExpenseForm.scanButton)
        } else {
            // No camera to offer — the simulator, and an iPad that has none. A menu with one item
            // in it is a menu nobody needs.
            Button { pickPhoto() } label: { scanLabel }
                .disabled(phase == .scanning)
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.scanButton)
        }
    }

    /// The spinner sits beside the label rather than replacing the row, so nothing moves while a
    /// receipt is being read — and the row goes on being the same row.
    private var scanLabel: some View {
        HStack {
            Label("Scan receipt", systemImage: "text.viewfinder")
            if phase == .scanning {
                Spacer()
                ProgressView()
            }
        }
    }

    private var status: LocalizedStringKey {
        switch phase {
        case .idle:
            "Take a photo of the receipt and Spliit fills in what it can read. It never leaves your iPhone."
        case .scanning:
            "Reading the receipt…"
        case .scanned(found: true):
            "Filled in from the receipt. Check it before saving."
        case .scanned(found: false):
            "Nothing on that photo looked like a receipt."
        case .failed:
            "Couldn’t read that photo. Try again with the whole receipt in frame."
        }
    }

    // MARK: - Picking

    /// Whether there is a camera to choose between.
    ///
    /// A simulator reports one it does not have, and it has no photo library worth driving
    /// either — so under UI test the row is the single button, which is what makes the suite
    /// about reading a receipt rather than about opening a menu.
    private var offersCamera: Bool {
        #if DEBUG
        if UITestSupport.usesSampleReceipt { return false }
        #endif
        return VNDocumentCameraViewController.isSupported
    }

    /// Under UI test there is no camera and no photo library worth driving, so the button scans
    /// a receipt the app draws for itself — through the real Vision pass and the real parser,
    /// which is the half of this that can break silently.
    private func pickPhoto() {
        #if DEBUG
        if let sample = UITestSupport.sampleReceipt() {
            scan(sample)
            return
        }
        #endif
        isShowingLibrary = true
    }

    private func loadPickedPhoto() async {
        guard let pickedItem else { return }
        defer { self.pickedItem = nil }

        guard let data = try? await pickedItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let photo = ReceiptPhoto(image)
        else {
            phase = .failed
            return
        }
        scan(photo)
    }

    // MARK: - Scanning

    private func scan(_ photo: ReceiptPhoto) {
        phase = .scanning
        Analytics.shared.event(.scanReceipt)

        Task {
            let scanner = ReceiptScanner(usesModel: usesModel)
            do {
                let scan = try await scanner.scan(
                    photo.image, orientation: photo.orientation, categories: categories
                )
                onScan(scan)
                phase = .scanned(found: !scan.isEmpty)
            } catch {
                phase = .failed
            }
        }
    }

    private var usesModel: Bool {
        #if DEBUG
        return !UITestSupport.usesSampleReceipt
        #else
        return true
        #endif
    }
}
