import Foundation

/// Puts a document where the instance keeps them, and says when it keeps them nowhere.
///
/// Not tRPC, and the one thing in this client that isn't. The web app uploads through
/// `next-s3-upload`, which puts a REST route at `/api/s3-upload` beside the tRPC one — and that
/// route never sees the file. It signs a `PUT` against the instance's own bucket and hands the
/// signature back, so the bytes go from here straight to the bucket; all tRPC ever learns is the
/// URL the object ended up at, which is the whole of what `ExpenseDocument` stores.
///
/// Two consequences worth knowing. **The upload happens before the expense is saved**, exactly as
/// it does on the web — a document is a URL by the time the form has one, and an expense the user
/// then abandons leaves an object nobody references. And **deleting a document only forgets its
/// URL**: neither product has ever removed the object, because neither has credentials to.
public struct DocumentUploader: Sendable {

    /// Why an upload didn't happen.
    public enum Failure: Error, Equatable, Sendable {
        /// This instance stores no documents. Not a fault and not worth retrying: document
        /// storage is optional in Spliit, the route is compiled in whether or not a bucket is
        /// configured, and it answers 500 with an empty body when the `S3_*` settings are
        /// missing. A self-hosted instance without a bucket is entirely ordinary.
        case unsupported
        case network(String)
        /// The bucket refused the upload the instance had just signed.
        case rejected(status: Int)
        /// The signing route answered with something that wasn't a signature.
        case malformedSignature
    }

    public let baseURL: URL
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: the instance root, as the group the expense belongs to stores it.
    ///   - session: defaults to one shared by every uploader.
    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.sharedSession
    }

    /// A photograph is a great deal more than a tRPC call, and over a phone connection it is
    /// slower than one by an order of magnitude. The 20 seconds `TRPCClient` allows itself would
    /// cut off uploads that were going to succeed.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Uploads one file and answers with the URL to store against the expense.
    ///
    /// - Parameters:
    ///   - data: the file itself.
    ///   - filename: only its extension survives — the route names the object
    ///     `document-<timestamp>-<random><ext>` and ignores the rest.
    ///   - contentType: stored on the object, and sent as a header on the upload.
    public func upload(
        _ data: Data,
        filename: String = "receipt.jpg",
        contentType: String = "image/jpeg"
    ) async throws -> String {
        let signature = try await sign(filename: filename, contentType: contentType)
        try await put(data, contentType: contentType, to: signature.url)
        return signature.publicURL
    }

    // MARK: - Signing

    /// What the route answers with: where to `PUT`, and everything needed to work out where the
    /// object will then be readable.
    struct Signature: Decodable, Equatable, Sendable {
        let key: String
        let bucket: String
        let region: String?
        /// Only set when the instance uses something other than AWS. Absent from the JSON
        /// otherwise, since `undefined` doesn't survive `JSON.stringify`.
        let endpoint: String?
        /// The presigned `PUT`, already percent-encoded. Used verbatim: re-deriving it would
        /// change the signature.
        let url: String

        /// Where the object will be readable once it is there.
        ///
        /// Derived rather than returned, because the route has no idea: it signs a request and
        /// the client works out the address, which is why both products have to agree on this
        /// formula. The web app's is in `next-s3-upload`; this is the same one, minus a trailing
        /// slash on a configured endpoint, which would otherwise double up.
        var publicURL: String {
            if let endpoint, !endpoint.isEmpty, endpoint != "undefined" {
                var trimmed = endpoint
                while trimmed.hasSuffix("/") { trimmed.removeLast() }
                return "\(trimmed)/\(bucket)/\(key)"
            }
            return "https://\(bucket).s3.\(region ?? "").amazonaws.com/\(key)"
        }
    }

    private struct SignatureRequest: Encodable {
        let filename: String
        let filetype: String
        /// Asks for a presigned `PUT` rather than the temporary IAM credentials the route
        /// otherwise mints. Presigning is what works against S3-compatible storage that has no
        /// STS to issue those credentials, which is most of what people self-host behind.
        let nextS3 = Strategy()

        struct Strategy: Encodable {
            let strategy = "presigned"
        }

        enum CodingKeys: String, CodingKey {
            case filename, filetype
            case nextS3 = "_nextS3"
        }
    }

    func sign(filename: String, contentType: String) async throws -> Signature {
        var request = URLRequest(url: try uploadRouteURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            SignatureRequest(filename: filename, filetype: contentType)
        )

        let (data, response) = try await send(request)

        // Which failure this is decides whether the app stops offering uploads for the rest of
        // the session, so the two are worth telling apart. 404 and 405 are an instance with no
        // such route; 500 is the route itself giving up, which is the whole of what
        // `NextResponse.error()` does when the S3 settings are missing — none of the three can
        // be retried into working. Anything else is a gateway or a proxy having a moment, and
        // that is worth trying again.
        switch response.statusCode {
        case 200..<300:
            break
        case 404, 405, 500:
            throw Failure.unsupported
        default:
            throw Failure.rejected(status: response.statusCode)
        }
        guard let signature = try? JSONDecoder().decode(Signature.self, from: data) else {
            throw Failure.malformedSignature
        }
        return signature
    }

    // MARK: - Uploading

    private func put(_ data: Data, contentType: String, to presigned: String) async throws {
        guard let url = URL(string: presigned) else { throw Failure.malformedSignature }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // Byte-identical to what the web app sends, cache lifetime included — twenty years,
        // which is what an object named after the moment it was created can safely claim.
        //
        // Whether either header is *covered* by the signature is the signing SDK's business and
        // not ours: today's answers list `host` alone in `X-Amz-SignedHeaders`, but a version
        // that also signed the content type would reject an upload that omitted it, and one that
        // signed a different cache lifetime would reject a different value. Sending exactly what
        // the other client sends is what makes that question none of this code's concern.
        request.setValue("max-age=630720000", forHTTPHeaderField: "Cache-Control")
        request.httpBody = data

        let (_, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.rejected(status: response.statusCode)
        }
    }

    // MARK: - Plumbing

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw Failure.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Failure.network("The response wasn’t an HTTP response.")
        }
        return (data, http)
    }

    func uploadRouteURL() throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil
        else {
            throw TRPCClientError.invalidBaseURL(baseURL.absoluteString)
        }
        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        components.path = path + "api/s3-upload"

        guard let url = components.url else {
            throw TRPCClientError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }
}

/// English, like `TRPCClientError`'s: this module has no catalogue of its own, and the sentence a
/// person actually reads about `.unsupported` is written by the screen that offers the upload,
/// which is the only one that knows what to suggest instead.
extension DocumentUploader.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported:
            "This Spliit instance doesn’t store documents."
        case .network(let reason):
            "Couldn’t reach the server. \(reason)"
        case .rejected(let status):
            "The upload was refused with status \(status)."
        case .malformedSignature:
            "The server’s answer couldn’t be read. It may be running a different version."
        }
    }
}

extension ExpenseDocument {
    /// An ID for a document about to be attached, in the shape the web app's `randomId()` makes.
    ///
    /// Which end mints it depends on the call: `groups.expenses.create` gives every document it
    /// is handed an ID of its own and drops this one, while `groups.expenses.update` writes what
    /// it is given. So this is the ID a document attached to an existing expense keeps, and it
    /// has to be unique in a table shared with the web app — twenty-one characters from nanoid's
    /// alphabet, which is what that column has held since it existed.
    public static func newID() -> String {
        // Exactly 64 characters, so a random index is uniform without any rejection sampling.
        let alphabet = Array("-_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        return String((0..<21).map { _ in alphabet.randomElement()! })
    }
}
