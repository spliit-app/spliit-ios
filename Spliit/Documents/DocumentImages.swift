import SpliitAPI
import SwiftUI

/// The pictures behind the documents on one screen: fetched once, kept while the screen is.
///
/// `AsyncImage` does most of this, but not the half that matters here. A document is as often a
/// photograph this app has *just uploaded* as one it is seeing for the first time, and
/// downloading a picture the phone still holds in memory is a round trip and a visible flash for
/// nothing. One cache shared by the thumbnails and the viewer also means opening a receipt shows
/// it rather than fetching it again — and the viewer needs a `UIImage` in any case, because the
/// zooming underneath it is a `UIScrollView`'s.
@Observable
@MainActor
final class DocumentImages {

    private var images: [String: UIImage] = [:]
    private var failures: Set<String> = []
    private var loading: Set<String> = []

    /// The picture for a document's URL, if it is to hand.
    subscript(url: String) -> UIImage? { images[url] }

    func hasFailed(_ url: String) -> Bool { failures.contains(url) }

    /// Takes the picture that was just uploaded, under the URL it landed at, so the thumbnail
    /// appears the moment the upload finishes instead of after fetching back what we just sent.
    func remember(_ image: UIImage, for url: String) {
        images[url] = image
        failures.remove(url)
    }

    func load(_ url: String) async {
        guard images[url] == nil, !loading.contains(url), let target = URL(string: url) else {
            return
        }
        loading.insert(url)
        defer { loading.remove(url) }

        do {
            // `URLSession.shared`, not the ephemeral one the API client uses: these objects are
            // served with a twenty-year cache lifetime, and a shared `URLCache` is the whole
            // reason a receipt looked at twice is fetched once.
            let (data, response) = try await URLSession.shared.data(from: target)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data)
            else {
                throw URLError(.cannotDecodeContentData)
            }
            images[url] = image
            failures.remove(url)
        } catch {
            // Nothing louder: a document whose bucket is unreachable is one tile that cannot be
            // drawn, not a reason to interrupt an expense somebody is in the middle of writing.
            failures.insert(url)
        }
    }
}

/// One document, drawn to fill a square.
struct DocumentThumbnail: View {

    let document: ExpenseDocument
    let images: DocumentImages

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = images[document.url] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if images.hasFailed(document.url) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .task(id: document.url) { await images.load(document.url) }
    }
}
