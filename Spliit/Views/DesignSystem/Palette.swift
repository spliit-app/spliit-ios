import SpliitCore
import SwiftUI

/// The colours the app adds on top of the system palette.
///
/// Backgrounds, separators and fills are deliberately absent: the system ones already adapt to
/// dark mode, to increased contrast, and to Apple's own drift between releases, and matching them
/// by hand is a debt that comes due every September. Only what the system has no opinion about is
/// defined here — the money axis and the monogram palette.
///
/// The names are the asset catalogue's, and this extension is the only place they appear.
extension Color {

    /// Owed to you. Emerald, darkened in light mode to clear AA against white.
    static let moneyPositive = Color("MoneyPositive")

    /// You owe. The logo's coral, darkened for light mode and lightened for dark.
    static let moneyNegative = Color("MoneyNegative")

    /// Pink-700. Rare by design — the monogram palette, and the occasional non-money accent.
    static let brandSecondary = Color("BrandSecondary")

    /// The accent at a whisper, for the tile an empty state's icon sits in. A tint rather than a
    /// translucency, so it does not change with whatever happens to be behind it.
    static let brandAccentSoft = Color("BrandAccentSoft")

    /// One of the eight monogram colours, by the index `MonogramPalette` derives from an ID.
    static func monogram(_ index: Int) -> Color {
        Color("Monogram\((index % MonogramPalette.count) + 1)")
    }
}
