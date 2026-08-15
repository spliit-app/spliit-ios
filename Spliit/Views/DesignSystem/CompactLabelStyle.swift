import SwiftUI

/// A label whose icon sits next to its text rather than in a reserved column.
///
/// `Label`'s default style leaves room for the widest icon it might have to align with, which is
/// right in a settings list and wrong in a caption: two of these side by side end up as icons and
/// text separated by a gap wide enough to read as four unrelated items.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}
