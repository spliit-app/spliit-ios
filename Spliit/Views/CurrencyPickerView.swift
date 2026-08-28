import SpliitCore
import SwiftUI

/// Choosing what a group counts in, or what one expense in it was paid in.
///
/// A hundred and fifty-nine currencies is far too many for a menu, so this is the shape iOS
/// uses for a long list of one-of choices: a pushed, searchable list, with the handful anyone
/// is likely to want at the top. Picking one sets the group's symbol as well as its code, which
/// is why the caller is handed a whole `Currency` rather than a string.
struct CurrencyPickerView: View {

    /// What the group carries now, or nil when it has only a symbol.
    let selectedCode: String?
    /// One more currency to offer at the top, when the caller has an obvious candidate — the
    /// group's own, on the screen that picks what an expense was paid in.
    var promotedCode: String?
    /// Whether "custom symbol" is one of the answers. It is for a group, which may be counted in
    /// anything at all; it is not for an expense, where a conversion needs a code on both sides.
    var allowsCustomSymbol = true
    /// The chosen currency, or nil for "custom symbol".
    let onSelect: (Currency?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let currencies = Currency.all()
    private let suggested = Currency.suggested()

    var body: some View {
        Group {
            if matches.isEmpty {
                noMatches
            } else {
                list
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Name or code")
        )
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        List {
            if isSearching {
                Section {
                    ForEach(matches) { row(for: $0) }
                }
            } else {
                Section("Suggested") {
                    ForEach(suggestions) { row(for: $0) }
                }

                // Above the full list rather than below it: a hundred and fifty-nine rows is a
                // long way to scroll for the one option that isn't in them.
                if allowsCustomSymbol {
                    Section {
                        customRow
                    } footer: {
                        Text("A custom symbol sits beside amounts the same way, but records no ISO code — so nothing else can tell what the amounts are in, and no expense in the group can be recorded in another currency.")
                    }
                }

                Section("All currencies") {
                    ForEach(currencies) { row(for: $0) }
                }
            }
        }
    }

    private var noMatches: some View {
        EmptyState(
            art: .icon("magnifyingglass"),
            title: Text("No matching currency"),
            description: Text("Nothing here matches “\(trimmedQuery)”.")
        ) {
            if allowsCustomSymbol {
                Button("Use a custom symbol") { choose(nil) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.CurrencyPicker.customOption)
            }
        }
    }

    private func row(for currency: Currency) -> some View {
        Button {
            choose(currency)
        } label: {
            HStack(spacing: 12) {
                if let flag = currency.flag {
                    // Decoration, and decoration that repeats the name: a screen reader saying
                    // "flag of Switzerland, Swiss Franc" is worse than saying the name once.
                    Text(flag)
                        .font(.title3)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.name)
                    Text(subtitle(for: currency))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                checkmark(isSelected: currency.code == selectedCode)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(currency.code == selectedCode ? [.isSelected] : [])
        .accessibilityIdentifier(AccessibilityID.CurrencyPicker.row(currency.code))
    }

    private var customRow: some View {
        Button {
            choose(nil)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom symbol")
                    Text("Type your own, for anything not listed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                checkmark(isSelected: selectedCode == nil)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCode == nil ? [.isSelected] : [])
        .accessibilityIdentifier(AccessibilityID.CurrencyPicker.customOption)
    }

    @ViewBuilder
    private func checkmark(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                // The trait on the row is what says "selected"; the tick is how it looks.
                .accessibilityHidden(true)
        }
    }

    /// The code, and the symbol too when it says something the code doesn't.
    private func subtitle(for currency: Currency) -> String {
        currency.symbol == currency.code
            ? currency.code
            : "\(currency.code) · \(currency.symbol)"
    }

    /// The handful offered above the full list, with the caller's own candidate first.
    private var suggestions: [Currency] {
        guard let promoted = promotedCode.flatMap({ Currency.named($0) }) else { return suggested }
        return [promoted] + suggested.filter { $0.code != promoted.code }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var matches: [Currency] {
        guard isSearching else { return currencies }
        return currencies.filter { $0.matches(trimmedQuery) }
    }

    private func choose(_ currency: Currency?) {
        onSelect(currency)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CurrencyPickerView(selectedCode: "CHF") { _ in }
    }
}
