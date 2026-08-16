import UIKit
import XCTest

/// The category glyphs, checked against the system that has to draw them.
///
/// `Image(systemName:)` with a name that does not exist draws nothing and says nothing — no
/// crash, no warning, just a row with a hole where the icon should be. A typo in the map would
/// otherwise survive review and ship. These run in the simulator but launch nothing, so they cost
/// no more than the bundle's own start-up.
final class CategoryIconTests: XCTestCase {

    func testEverySymbolExists() {
        for (category, symbol) in ExpenseCategoryIcon.symbols {
            XCTAssertNotNil(
                UIImage(systemName: symbol),
                "\(category) maps to \"\(symbol)\", which is not an SF Symbol on this system."
            )
        }
    }

    func testTheFallbackExists() {
        XCTAssertNotNil(
            UIImage(systemName: ExpenseCategoryIcon.fallback),
            "Every unmapped category falls back to this one, so it had better draw."
        )
    }

    /// The web app's `category-icon.tsx` has an arm for each of these. A category that loses its
    /// glyph here still renders — it silently falls back to a banknote — so the count is the only
    /// thing that catches an accidental deletion.
    func testEveryCategoryTheWebAppKnowsIsMapped() {
        XCTAssertEqual(
            ExpenseCategoryIcon.symbols.count, 44,
            "The web app maps 44 categories; this map should have an entry for each."
        )
    }

    /// Several category names contain a slash, so the key is built by concatenation rather than
    /// by splitting. This is the one that would break first if that changed.
    func testCategoryNamesContainingSlashesResolve() {
        XCTAssertEqual(
            ExpenseCategoryIcon.symbol(grouping: "Transportation", name: "Bus/Train"), "tram"
        )
        XCTAssertEqual(
            ExpenseCategoryIcon.symbol(grouping: "Utilities", name: "TV/Phone/Internet"), "phone"
        )
    }

    func testAnUnknownCategoryFallsBack() {
        XCTAssertEqual(
            ExpenseCategoryIcon.symbol(grouping: "Something", name: "New"),
            ExpenseCategoryIcon.fallback
        )
        XCTAssertEqual(
            ExpenseCategoryIcon.symbol(grouping: nil, name: nil), ExpenseCategoryIcon.fallback
        )
    }

    /// A category needs a glyph *and* a word, and the two maps are written out by hand from the
    /// same upstream list. Either one can be forgotten on its own without anything failing —
    /// the glyph falls back to a banknote and the word falls back to the server's English — so
    /// this is what says they are still the same set.
    ///
    /// This asserts the map has an arm, not that the arm is translated: these run in the test
    /// bundle, which carries no catalogue, so every lookup here comes back English. Whether the
    /// French is actually present is `make strings`' job.
    func testEveryCategoryWithAGlyphAlsoHasAName() {
        for key in ExpenseCategoryIcon.symbols.keys {
            // "Bus/Train" and friends put a slash in the name, so only the first component is
            // the grouping.
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            let (grouping, name) = (parts[0], parts[1])

            XCTAssertNotNil(
                ExpenseCategoryName.name(grouping: grouping, name: name),
                "\(key) has a glyph but no name, so it would show the server's English."
            )
            XCTAssertNotNil(
                ExpenseCategoryName.heading(grouping),
                "\(grouping) heads a section of the picker with no translated heading."
            )
        }
    }

    func testAnUnknownCategoryHasNoNameRatherThanAWrongOne() {
        XCTAssertNil(ExpenseCategoryName.name(grouping: "Something", name: "New"))
        XCTAssertNil(ExpenseCategoryName.heading("Something"))
    }
}
