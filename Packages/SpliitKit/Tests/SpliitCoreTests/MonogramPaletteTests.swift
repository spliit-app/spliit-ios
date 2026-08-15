import Testing

@testable import SpliitCore

/// A monogram colour that moves is worse than no colour at all: the whole point is that you learn
/// to recognise someone by it. These pin the two ways it could move — between launches, and
/// between an old build and a new one.
@Suite("Monogram palette")
struct MonogramPaletteTests {

    @Test("Every index lands inside the palette")
    func indexIsInRange() {
        for seed in ["", "a", "clx1v9m2h0000abcd", "🙂", String(repeating: "x", count: 500)] {
            let index = MonogramPalette.index(for: seed)
            #expect(index >= 0)
            #expect(index < MonogramPalette.count)
        }
    }

    @Test("The same ID always gives the same colour")
    func indexIsStable() {
        let seed = "clx1v9m2h0000abcd"
        let first = MonogramPalette.index(for: seed)
        #expect(MonogramPalette.index(for: seed) == first)
        #expect(MonogramPalette.index(for: seed) == first)
    }

    /// The values themselves, not just their stability. `hashValue` would pass the test above
    /// within a single process and still hand out different colours after a relaunch — only
    /// checked-in expectations catch a hash being swapped for one that reshuffles everyone.
    @Test("The mapping is the one that shipped")
    func indexMatchesRecordedValues() {
        #expect(MonogramPalette.index(for: "participant-1") == 0)
        #expect(MonogramPalette.index(for: "participant-2") == 1)
        #expect(MonogramPalette.index(for: "ana") == 5)
        #expect(MonogramPalette.index(for: "bruno") == 7)
    }

    @Test("Different participants mostly get different colours")
    func indexIsSpread() {
        let indices = Set((0..<200).map { MonogramPalette.index(for: "participant-\($0)") })
        #expect(indices.count == MonogramPalette.count)
    }

    @Test("Initials come from the first two words")
    func initials() {
        #expect(MonogramPalette.initials(for: "Sébastien Castiel") == "SC")
        #expect(MonogramPalette.initials(for: "Jane") == "J")
        #expect(MonogramPalette.initials(for: "ana maria silva") == "AM")
        #expect(MonogramPalette.initials(for: "  padded   name  ") == "PN")
    }

    @Test("A nameless participant gets a blank chip, not a placeholder")
    func initialsOfEmptyName() {
        #expect(MonogramPalette.initials(for: "") == "")
        #expect(MonogramPalette.initials(for: "   ") == "")
    }
}
