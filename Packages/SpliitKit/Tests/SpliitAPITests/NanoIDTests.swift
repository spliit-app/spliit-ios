import Foundation
import Testing

@testable import SpliitAPI

/// The server validates a client-minted expense ID against `/^[A-Za-z0-9_-]{21}$/` and refuses
/// the create outright when it does not match, so the shape is pinned here rather than found
/// out from a 400.
@Suite("Minting IDs")
struct NanoIDTests {

    @Test("An ID is what the server's schema takes")
    func matchesTheServerPattern() throws {
        for _ in 0..<100 {
            let id = NanoID.generate()
            #expect(id.count == 21)
            #expect(id.wholeMatch(of: /^[A-Za-z0-9_-]{21}$/) != nil, "\(id)")
        }
    }

    /// Every character of the alphabet turns up, so this is nanoid's 64-symbol alphabet and not
    /// a narrower one that happens to satisfy the pattern: `-` and `_` are the two easiest to
    /// lose, and an ID space of 62 symbols is not the one the server's own IDs are drawn from.
    @Test("The whole URL-safe alphabet is in use")
    func drawsFromTheWholeAlphabet() {
        var seen: Set<Character> = []
        for _ in 0..<2000 {
            seen.formUnion(NanoID.generate())
        }
        #expect(seen == Set(NanoID.alphabet))
        #expect(seen.count == 64)
    }

    @Test("Two IDs are two IDs")
    func doesNotRepeat() {
        let ids = (0..<1000).map { _ in NanoID.generate() }
        #expect(Set(ids).count == ids.count)
    }
}
