import SpliitCore
import SwiftUI

/// Someone's initials, in a colour that is theirs.
///
/// Spliit has no accounts and no avatars, so a participant has only ever been a name in a row.
/// A monogram gives the eye something to find: the same person is the same colour in the balances,
/// in the expense list and in a suggested payment, on every device.
struct Monogram: View {

    let name: String
    let colorIndex: Int
    var size: CGFloat = 28

    @ScaledMetric private var textScale: CGFloat = 1

    /// A participant, coloured by their position in the group — which is what stops two members of
    /// the same group from being handed the same colour.
    init(name: String, position: Int, size: CGFloat = 28) {
        self.name = name
        self.colorIndex = MonogramPalette.index(atPosition: position)
        self.size = size
    }

    /// A group, coloured by its ID. The home screen reorders itself as groups are opened, so a
    /// position here would mean a group changing colour for having been looked at.
    init(name: String, seed: String, size: CGFloat = 28) {
        self.name = name
        self.colorIndex = MonogramPalette.index(for: seed)
        self.size = size
    }

    var body: some View {
        Text(MonogramPalette.initials(for: name))
            .font(.system(size: side * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Color.monogram(colorIndex), in: Circle())
            // It repeats the name it sits beside, so reading it aloud would say everything twice.
            .accessibilityHidden(true)
    }

    /// Growing with the text keeps the chip in proportion with the name beside it. The cap is
    /// what stops it from becoming the row: at the largest accessibility size an uncapped circle
    /// is wider than the screen, and the name and the amount are what the row is actually for.
    private var side: CGFloat {
        size * min(textScale, 1.6)
    }
}

/// A participant reduced to nothing but their colour.
///
/// For the places where the names are already written out in a sentence — a monogram there would
/// repeat the text and shout over it, but a dot ties the row to the same colour language the
/// balances use.
struct ParticipantDot: View {

    let colorIndex: Int
    var size: CGFloat = 8

    @ScaledMetric private var textScale: CGFloat = 1

    init(position: Int, size: CGFloat = 8) {
        self.colorIndex = MonogramPalette.index(atPosition: position)
        self.size = size
    }

    var body: some View {
        let side = size * min(textScale, 1.6)
        Circle()
            .fill(Color.monogram(colorIndex))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(["Sébastien Castiel", "Jane", "ana maria silva", "Bruno"].enumerated()),
                id: \.offset) { position, name in
            HStack(spacing: 12) {
                Monogram(name: name, position: position)
                ParticipantDot(position: position)
                Text(name)
            }
        }
    }
    .padding()
}
