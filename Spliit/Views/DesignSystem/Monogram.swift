import SpliitCore
import SwiftUI

/// Someone's initials, in a colour that is theirs.
///
/// Spliit has no accounts and no avatars, so a participant has only ever been a name in a row.
/// A monogram gives the eye something to find: the same person is the same colour in the balances,
/// in the split list and in a suggested payment, on every device and after any rename.
struct Monogram: View {

    let name: String
    /// The participant's ID — never their name, so the colour survives a rename.
    let seed: String
    /// Diameter at the default text size.
    var size: CGFloat = 28

    @ScaledMetric private var textScale: CGFloat = 1

    var body: some View {
        Text(MonogramPalette.initials(for: name))
            .font(.system(size: side * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Color.monogram(MonogramPalette.index(for: seed)), in: Circle())
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

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(["Sébastien Castiel", "Jane", "ana maria silva", "Bruno"], id: \.self) { name in
            HStack(spacing: 12) {
                Monogram(name: name, seed: name)
                Text(name)
            }
        }
    }
    .padding()
}
