import Foundation

/// Raw API responses captured from a real Spliit instance by `e2e/seed.mjs --dump`.
///
/// Testing the decoders against recorded traffic rather than hand-written JSON is the point:
/// hand-written fixtures only prove the decoder agrees with our assumptions, not with the
/// server. Refresh them with:
///
///     make fixtures
enum Fixture {
    enum Failure: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let name):
                "No fixture named “\(name).json”. Run `make fixtures` to record it."
            }
        }
    }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw Failure.missing(name)
        }
        return try Data(contentsOf: url)
    }
}
