import SpliitAPI
import SwiftUI

/// A document at full size, with the expense's others beside it.
///
/// The web app's viewer is a carousel with a delete and a close; this is the same, plus the
/// zooming, which a phone needs and a desktop browser mostly doesn't — a receipt photographed at
/// arm's length is a page of four-point type until you can pinch it.
struct DocumentGalleryView: View {

    @Environment(\.dismiss) private var dismiss

    /// Bound rather than passed: deleting happens in here, and the form behind has to be looking
    /// at the same list — otherwise closing the viewer would bring the document back.
    @Binding var documents: [ExpenseDocument]
    let images: DocumentImages

    @State private var selection: ExpenseDocument.ID

    init(
        documents: Binding<[ExpenseDocument]>,
        images: DocumentImages,
        startingAt: ExpenseDocument.ID
    ) {
        _documents = documents
        self.images = images
        _selection = State(initialValue: startingAt)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(documents) { document in
                    ZoomableDocument(document: document, images: images)
                        .tag(document.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: documents.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .background(.black)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(position)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Documents.doneButton)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Remove", systemImage: "trash", role: .destructive, action: remove)
                        // The white tint below is what makes "Done" legible on black, and it
                        // takes the destructive red with it unless this puts it back.
                        .tint(.red)
                        .accessibilityIdentifier(AccessibilityID.Documents.removeButton)
                }
            }
        }
        // `preferredColorScheme(.dark)` would be the obvious way to get light chrome on black,
        // and it is the wrong one: it writes to the *window*, not to this view, so the sheet
        // underneath stayed dark after the viewer closed. The environment override reaches only
        // what is inside here, and the tint is what the two toolbar buttons read from.
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }

    /// "2 of 3", and nothing at all when there is only the one — a counter that never counts is
    /// just a word in the title bar.
    private var position: String {
        guard documents.count > 1,
              let index = documents.firstIndex(where: { $0.id == selection })
        else { return "" }
        return String(localized: "\(index + 1) of \(documents.count)")
    }

    /// Forgets the document — which is all either product has ever done. Neither has credentials
    /// for the bucket, so the object stays where it is; what changes is that the expense stops
    /// pointing at it, once the expense is saved.
    ///
    /// What is left is worked out from a copy rather than by reading the binding back after
    /// writing it. A binding is only as fresh as its getter, and one built over a value captured
    /// when the caller's body last ran will happily answer with the document that has just been
    /// removed.
    private func remove() {
        var remaining = documents
        guard let index = remaining.firstIndex(where: { $0.id == selection }) else { return }
        remaining.remove(at: index)
        documents = remaining

        guard !remaining.isEmpty else {
            dismiss()
            return
        }
        selection = remaining[min(index, remaining.count - 1)].id
    }
}

/// One page of the gallery: the picture once it is there, and an honest placeholder until it is.
private struct ZoomableDocument: View {

    let document: ExpenseDocument
    let images: DocumentImages

    var body: some View {
        Group {
            if let image = images[document.url] {
                ZoomableImage(image: image)
            } else if images.hasFailed(document.url) {
                ContentUnavailableView(
                    "Couldn’t load this document",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("The server it is stored on didn’t answer.")
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .task(id: document.url) { await images.load(document.url) }
    }
}

/// The picture, pinchable and pannable.
///
/// A `UIScrollView` rather than gestures of our own: pinch, pan, double-tap, the rubber-banding
/// at the edges and the way the three of them hand off to each other are a great deal of
/// behaviour to reimplement, and all of it is behaviour people already know.
private struct ZoomableImage: UIViewRepresentable {

    let image: UIImage

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView(image: image)
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.show(image)
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {

    private let imageView = UIImageView()

    init(image: UIImage) {
        super.init(frame: .zero)

        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        zoomScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only while the picture is sitting still. Re-fitting it on every layout pass would
        // undo the zoom the moment anything else on screen changed.
        if zoomScale == 1 { fitImage() }
        centreImage()
    }

    /// Sizes the image view to the picture rather than to the screen, so panning at six times
    /// magnification reaches the corners of the receipt instead of the black beside it.
    private func fitImage() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0
        else { return }

        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }

    private func centreImage() {
        contentInset = UIEdgeInsets(
            top: max(0, (bounds.height - contentSize.height) / 2),
            left: max(0, (bounds.width - contentSize.width) / 2),
            bottom: max(0, (bounds.height - contentSize.height) / 2),
            right: max(0, (bounds.width - contentSize.width) / 2)
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard zoomScale == minimumZoomScale else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        // Three times, centred on what was tapped — the gesture people use to read one line of a
        // receipt, rather than to look at the middle of it.
        let scale: CGFloat = 3
        let point = gesture.location(in: imageView)
        zoom(
            to: CGRect(
                x: point.x - bounds.width / (2 * scale),
                y: point.y - bounds.height / (2 * scale),
                width: bounds.width / scale,
                height: bounds.height / scale
            ),
            animated: true
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centreImage() }
}
