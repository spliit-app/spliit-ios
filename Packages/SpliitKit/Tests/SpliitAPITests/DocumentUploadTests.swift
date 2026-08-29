import Foundation
import Testing

@testable import SpliitAPI

/// Answers a scripted sequence of responses and keeps every request it was given.
///
/// An upload is two round trips that have to agree with each other — the second one is signed by
/// the first, and a header this client forgets is a signature the bucket rejects. One stub that
/// records both is what lets a test assert on the pair.
final class UploadStubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Recorded: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
    }

    /// Consumed in order, one per request.
    nonisolated(unsafe) static var answers: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var received: [Recorded] = []

    static func session() -> URLSession {
        received = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.received.append(
            Recorded(
                url: request.url!,
                method: request.httpMethod ?? "",
                headers: request.allHTTPHeaderFields ?? [:],
                body: Self.body(of: request)
            )
        )

        let answer = Self.answers.isEmpty ? (status: 200, body: "") : Self.answers.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `URLSession` hands a `URLProtocol` the body as a stream more often than not, whatever the
    /// caller set — so both have to be read, or every body assertion quietly passes on nothing.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite("Document uploads", .serialized)
struct DocumentUploadTests {

    private let signature = """
        {"key":"document-2026-08-29T10:00:00.000Z-abc.jpg","bucket":"spliit",\
        "region":"eu-west-3","url":"https://spliit.s3.eu-west-3.amazonaws.com/x?X-Amz-Signature=s"}
        """

    private func uploader() -> DocumentUploader {
        DocumentUploader(
            baseURL: URL(string: "https://spliit.example.com/")!,
            session: UploadStubURLProtocol.session()
        )
    }

    @Test("Signing asks the instance's own route for a presigned PUT")
    func asksForAPresignedPut() async throws {
        UploadStubURLProtocol.answers = [(200, signature), (200, "")]

        _ = try await uploader().upload(Data("jpeg".utf8), filename: "receipt.jpg")

        let sign = try #require(UploadStubURLProtocol.received.first)
        #expect(sign.url.absoluteString == "https://spliit.example.com/api/s3-upload")
        #expect(sign.method == "POST")
        #expect(sign.json["filename"] as? String == "receipt.jpg")
        #expect(sign.json["filetype"] as? String == "image/jpeg")
        // Without this the route mints temporary IAM credentials instead, which only AWS itself
        // can issue — and most self-hosted Spliit instances are not on AWS.
        let strategy = sign.json["_nextS3"] as? [String: Any]
        #expect(strategy?["strategy"] as? String == "presigned")
    }

    /// These two are not decoration. Which headers a presigned URL covers is decided by the
    /// signing SDK on the far side — today's answers name `host` and nothing else — and a version
    /// that covered the content type would refuse an upload that left it out. Sending exactly
    /// what the web app sends is what keeps that from ever being this client's problem.
    @Test("The upload sends the same headers the web app does")
    func sendsTheSignedHeaders() async throws {
        UploadStubURLProtocol.answers = [(200, signature), (200, "")]

        _ = try await uploader().upload(Data("jpeg".utf8), contentType: "image/jpeg")

        let put = try #require(UploadStubURLProtocol.received.last)
        #expect(put.method == "PUT")
        #expect(put.url.absoluteString.contains("X-Amz-Signature=s"))
        #expect(put.headers["Content-Type"] == "image/jpeg")
        #expect(put.headers["Cache-Control"] == "max-age=630720000")
        #expect(put.body == Data("jpeg".utf8))
    }

    @Test("The stored URL is where the object ended up, not where it was uploaded to")
    func returnsThePublicURL() async throws {
        UploadStubURLProtocol.answers = [(200, signature), (200, "")]

        let url = try await uploader().upload(Data("jpeg".utf8))

        #expect(
            url == "https://spliit.s3.eu-west-3.amazonaws.com/"
                + "document-2026-08-29T10:00:00.000Z-abc.jpg"
        )
    }

    /// Most self-hosted instances point `S3_UPLOAD_ENDPOINT` at something that isn't AWS, and
    /// then the address is path-style. Both products have to derive the same one, because either
    /// can be the one that attached the document.
    @Test("A configured endpoint gives a path-style address")
    func derivesPathStyleAddresses() {
        let signature = DocumentUploader.Signature(
            key: "document-1.jpg",
            bucket: "spliit",
            region: nil,
            endpoint: "https://minio.example.com",
            url: "ignored"
        )

        #expect(signature.publicURL == "https://minio.example.com/spliit/document-1.jpg")
    }

    @Test("A trailing slash on the endpoint doesn't double up")
    func trimsTheEndpointSlash() {
        let signature = DocumentUploader.Signature(
            key: "document-1.jpg",
            bucket: "spliit",
            region: nil,
            endpoint: "https://minio.example.com/",
            url: "ignored"
        )

        #expect(signature.publicURL == "https://minio.example.com/spliit/document-1.jpg")
    }

    /// The case that decides whether the feature appears at all: document storage is optional,
    /// and an instance without a bucket answers 500 with an empty body — `NextResponse.error()`,
    /// which is all next-s3-upload does when its settings are missing.
    @Test("An instance with no bucket configured reports unsupported, not an error")
    func reportsUnsupportedStorage() async {
        UploadStubURLProtocol.answers = [(500, "")]

        await #expect(throws: DocumentUploader.Failure.unsupported) {
            _ = try await self.uploader().upload(Data("jpeg".utf8))
        }
    }

    /// An instance predating the route at all.
    @Test("A missing route reports unsupported too")
    func reportsMissingRoute() async {
        UploadStubURLProtocol.answers = [(404, "<html>404</html>")]

        await #expect(throws: DocumentUploader.Failure.unsupported) {
            _ = try await self.uploader().upload(Data("jpeg".utf8))
        }
    }

    /// A proxy having a moment is not an instance without a bucket, and treating it as one would
    /// stop offering uploads for the rest of the session over something that fixes itself.
    @Test("A gateway error is worth retrying rather than giving up on")
    func reportsATransientFailureAsSuch() async {
        UploadStubURLProtocol.answers = [(502, "<html>Bad Gateway</html>")]

        await #expect(throws: DocumentUploader.Failure.rejected(status: 502)) {
            _ = try await self.uploader().upload(Data("jpeg".utf8))
        }
    }

    @Test("A bucket that refuses the upload is a failure, not unsupported storage")
    func reportsARefusedUpload() async {
        UploadStubURLProtocol.answers = [(200, signature), (403, "AccessDenied")]

        await #expect(throws: DocumentUploader.Failure.rejected(status: 403)) {
            _ = try await self.uploader().upload(Data("jpeg".utf8))
        }
    }

    @Test("A signature that isn't one is reported as such")
    func reportsAMalformedSignature() async {
        UploadStubURLProtocol.answers = [(200, "{\"unexpected\":true}")]

        await #expect(throws: DocumentUploader.Failure.malformedSignature) {
            _ = try await self.uploader().upload(Data("jpeg".utf8))
        }
    }

    @Test("An instance address with a path keeps it")
    func buildsTheRouteUnderASubPath() throws {
        let uploader = DocumentUploader(baseURL: URL(string: "https://example.com/spliit")!)

        #expect(
            try uploader.uploadRouteURL().absoluteString == "https://example.com/spliit/api/s3-upload"
        )
    }

    /// The ID only matters on an update — a create mints its own — but it lands in a primary key
    /// shared with the web app, so it has to be shaped like the ones already in there.
    @Test("A new document ID looks like the ones the web app writes")
    func mintsNanoIDs() {
        let ids = (0..<200).map { _ in ExpenseDocument.newID() }

        #expect(ids.allSatisfy { $0.count == 21 })
        #expect(Set(ids).count == ids.count)
        let allowed = CharacterSet(
            charactersIn: "-_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        )
        #expect(ids.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) })
    }
}
