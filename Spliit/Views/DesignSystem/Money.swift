import SwiftUI

/// Every amount in the app, in one treatment.
///
/// Money is what Spliit is for, so it gets a typeface of its own — rounded, tabular, slightly
/// tightened — rather than the semibold body text it used to be. Four sizes, chosen by how much
/// the number matters on the screen it is on, and a sign that is carried by colour only where the
/// amount actually has a direction.
struct Money: View {

    enum Size {
        /// A balance headline or a total.
        case hero
        /// A suggested payment.
        case lead
        /// A list row.
        case row
        /// An inline aside.
        case support

        /// Text styles, not point sizes, so every amount scales with Dynamic Type. These are the
        /// styles whose default sizes are the 34 / 22 / 17 / 13 the design system specifies.
        var textStyle: Font.TextStyle {
            switch self {
            case .hero: .largeTitle
            case .lead: .title2
            case .row: .body
            case .support: .footnote
            }
        }
    }

    enum Sign {
        /// An expense amount. It has no direction, so it carries no colour.
        case none
        case positive
        case negative
        case settled

        /// - Parameter balance: minor units, where negative means this participant owes.
        init(balance: Int) {
            if balance > 0 {
                self = .positive
            } else if balance < 0 {
                self = .negative
            } else {
                self = .settled
            }
        }

        var tint: Color {
            switch self {
            case .none: .primary
            case .positive: .moneyPositive
            case .negative: .moneyNegative
            case .settled: .secondary
            }
        }
    }

    /// Preformatted by `MoneyFormatter`.
    ///
    /// Never assemble this in a view, and never split the currency symbol into an element of its
    /// own: the UI suite asserts that an amount's accessibility label is exactly what the
    /// formatter produced, and a screen reader reading "dollar" and "20.00" as two labels is the
    /// bug that assertion exists to catch.
    let value: String
    var size: Size = .row
    var sign: Sign = .none
    /// Reimbursements read as an aside rather than a charge, matching how the expense list has
    /// always drawn their titles.
    var isReimbursement = false

    var body: some View {
        Text(value)
            .font(
                .system(
                    size.textStyle,
                    design: .rounded,
                    weight: isReimbursement ? .regular : .semibold
                )
                .monospacedDigit()
            )
            .tracking(-0.2)
            .italic(isReimbursement)
            .foregroundStyle(sign.tint)
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 16) {
        Money(value: "$84.20", size: .hero, sign: .positive)
        Money(value: "-$52.00", size: .lead, sign: .negative)
        Money(value: "$12.34", size: .row)
        Money(value: "$8.00", size: .row, isReimbursement: true)
        Money(value: "$0.00", size: .support, sign: .settled)
    }
    .padding()
}
