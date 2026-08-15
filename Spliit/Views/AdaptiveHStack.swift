import SwiftUI

/// Lays its content out in a row, and in a column once the text size reaches the accessibility
/// range.
///
/// A name beside an amount reads fine at the default size and becomes two truncated columns at
/// AX5, where neither half is legible. Stacking at that point is what the system apps do, and it
/// costs nothing at ordinary sizes.
///
/// Give the leading view `.frame(maxWidth: .infinity, alignment: .leading)` rather than a
/// `Spacer()` between the two: a spacer that pushes a trailing view sideways in a row expands
/// downwards in a column, leaving a gap the height of the list.
struct AdaptiveHStack<Content: View>: View {

    /// Defaults to `HStack`'s own alignment, so swapping one for the other changes nothing
    /// until the text gets large.
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout { content }
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
    }
}
