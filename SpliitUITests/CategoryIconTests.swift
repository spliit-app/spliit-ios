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
}
