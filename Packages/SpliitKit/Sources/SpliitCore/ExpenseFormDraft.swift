import Foundation
import SpliitAPI

/// One participant's row in the "Paid for" list.
public struct ParticipantShareDraft: Identifiable, Equatable, Sendable {
    /// The server-side participant ID.
    public let id: String
    public var name: String
    public var isIncluded: Bool
    /// What the user typed: a share count, a percentage, or an amount, depending on the
    /// split mode. Unused when splitting evenly.
    public var valueText: String

    public init(id: String, name: String, isIncluded: Bool = false, valueText: String = "1") {
        self.id = id
        self.name = name
        self.isIncluded = isIncluded
        self.valueText = valueText
    }
}

/// The expense form's state, plus the validation the server would apply.
///
/// Mirrors `expenseFormSchema` in the web app, including the split-mode sum rules that are the
/// easiest thing to get subtly wrong.
public struct ExpenseFormDraft: Equatable, Sendable {

    public var title: String
    public var expenseDate: Date
    /// The total, as typed.
    public var amountText: String
    public var categoryID: Int
    public var paidByID: String?
    public var splitMode: SplitMode
    public var participants: [ParticipantShareDraft]
    /// Whether this split should become the one the group's next expense starts from.
    ///
    /// Always starts off, editing included: remembering a split is something to ask for, and a
    /// box that arrives ticked would rewrite the default every time somebody corrected a typo.
    public var saveSplitAsDefault: Bool
    public var isReimbursement: Bool
    public var notes: String
    /// Used to parse typed numbers; a comma is the decimal separator in much of the world.
    public var locale: Locale
    /// How many digits the group's currency keeps behind the decimal point, so "1234" typed in
    /// a yen group is ¥1,234 rather than a hundredth of that. Only the total and the by-amount
    /// shares scale with it; share counts and percentages are ×100 whatever the currency.
    public var minorUnitDigits: Int

    /// Preserved across an edit so saving from the app doesn't drop what the web app set.
    public var recurrenceRule: RecurrenceRule
    public var documents: [ExpenseDocument]

    // MARK: Currency of the expense

    /// The group's ISO code, or nil when it has only a free-text symbol. Conversion needs one:
    /// without it there is nothing to convert *to*.
    public var groupCurrencyCode: String?
    /// What this expense was actually paid in. Starts as the group's own currency, and only
    /// means anything once it differs from it.
    public var originalCurrencyCode: String?
    /// What was paid, as typed, in `originalCurrencyCode`.
    public var originalAmountText: String
    /// One unit of `originalCurrencyCode` in the group's currency, as typed. A rate, not money:
    /// it is never scaled by anyone's minor units.
    public var conversionRateText: String

    public init(
        title: String = "",
        expenseDate: Date = .now,
        amountText: String = "",
        categoryID: Int = 0,
        paidByID: String? = nil,
        splitMode: SplitMode = .evenly,
        participants: [ParticipantShareDraft] = [],
        saveSplitAsDefault: Bool = false,
        isReimbursement: Bool = false,
        notes: String = "",
        locale: Locale = .autoupdatingCurrent,
        minorUnitDigits: Int = 2,
        recurrenceRule: RecurrenceRule = .never,
        documents: [ExpenseDocument] = [],
        groupCurrencyCode: String? = nil,
        originalCurrencyCode: String? = nil,
        originalAmountText: String = "",
        conversionRateText: String = ""
    ) {
        self.title = title
        self.expenseDate = expenseDate
        self.amountText = amountText
        self.categoryID = categoryID
        self.paidByID = paidByID
        self.splitMode = splitMode
        self.participants = participants
        self.saveSplitAsDefault = saveSplitAsDefault
        self.isReimbursement = isReimbursement
        self.notes = notes
        self.locale = locale
        self.minorUnitDigits = minorUnitDigits
        self.recurrenceRule = recurrenceRule
        self.documents = documents
        self.groupCurrencyCode = groupCurrencyCode
        self.originalCurrencyCode = originalCurrencyCode
        self.originalAmountText = originalAmountText
        self.conversionRateText = conversionRateText
    }

    /// A blank expense for a group: everyone included, split evenly — or divided however this
    /// group's expenses were last said to be divided.
    ///
    /// - Parameters:
    ///   - paidBy: whoever the user said they are in this group, when they have said. An ID the
    ///     group no longer has falls back to the first participant, which is what this form
    ///     filled in before anybody could answer the question.
    ///   - defaultSplit: what the group remembers, if anything. One naming somebody who has
    ///     since left is ignored rather than trimmed, so a stale default can never quietly leave
    ///     a participant out of the expense being written.
    public init(
        creatingIn group: Group,
        paidBy: String? = nil,
        defaultSplit: DefaultSplit? = nil,
        locale: Locale = .autoupdatingCurrent
    ) {
        let payer = group.participants.first { $0.id == paidBy } ?? group.participants.first
        let split = defaultSplit.flatMap { $0.applies(to: group.participants) ? $0 : nil }
        let digits = Self.minorUnitDigits(for: group, locale: locale)

        self.init(
            paidByID: payer?.id,
            splitMode: split?.splitMode ?? .evenly,
            participants: group.participants.map { participant in
                let shares = split?.shares?[participant.id]
                return ParticipantShareDraft(
                    id: participant.id,
                    name: participant.name,
                    // With nothing remembered — and under `.byAmount`, which remembers no shares
                    // — the split covers the group, which is how a new expense has always begun.
                    isIncluded: split?.shares == nil || shares != nil,
                    valueText: shares.map {
                        Self.text(
                            forShares: $0,
                            splitMode: split?.splitMode ?? .evenly,
                            locale: locale,
                            minorUnitDigits: digits
                        )
                    } ?? "1"
                )
            },
            locale: locale,
            minorUnitDigits: digits,
            groupCurrencyCode: group.currencyCode,
            originalCurrencyCode: group.currencyCode
        )
    }

    /// An expense loaded for editing.
    public init(
        editing expense: ExpenseDetails,
        group: Group,
        locale: Locale = .autoupdatingCurrent
    ) {
        let sharesByParticipant = Dictionary(
            expense.paidFor.map { ($0.participantId, $0.shares) },
            uniquingKeysWith: { first, _ in first }
        )
        let digits = Self.minorUnitDigits(for: group, locale: locale)
        // An expense saved before the group had a code, or one saved in the group's own
        // currency, has no currency of its own — it is in whatever the group counts in. The
        // amount and rate beside it may still hold what a conversion it no longer has left
        // there, since the server has no way to clear those two; without a currency they mean
        // nothing, so they are not read back.
        let originalCode = expense.originalCurrency ?? group.currencyCode
        let wasConverted = expense.originalCurrency != nil
        let originalDigits = MoneyFormatter.minorUnitDigits(
            forCurrencyCode: originalCode, locale: locale
        )

        self.init(
            title: expense.title,
            expenseDate: expense.expenseDate,
            amountText: Self.text(
                forMinorUnits: expense.amount, locale: locale, minorUnitDigits: digits
            ),
            categoryID: expense.categoryId,
            paidByID: expense.paidById,
            splitMode: expense.splitMode,
            participants: group.participants.map { participant in
                let shares = sharesByParticipant[participant.id]
                return ParticipantShareDraft(
                    id: participant.id,
                    name: participant.name,
                    isIncluded: shares != nil,
                    valueText: Self.text(
                        forShares: shares ?? 100,
                        splitMode: expense.splitMode,
                        locale: locale,
                        minorUnitDigits: digits
                    )
                )
            },
            isReimbursement: expense.isReimbursement,
            notes: expense.notes ?? "",
            locale: locale,
            minorUnitDigits: digits,
            recurrenceRule: expense.recurrenceRule ?? .never,
            documents: expense.documents,
            groupCurrencyCode: group.currencyCode,
            originalCurrencyCode: originalCode,
            originalAmountText: wasConverted ? expense.originalAmount.map {
                Self.text(forMinorUnits: $0, locale: locale, minorUnitDigits: originalDigits)
            } ?? "" : "",
            conversionRateText: wasConverted ? expense.conversionRate.map {
                Self.text(forRate: $0.value, locale: locale)
            } ?? "" : ""
        )
    }

    /// A reimbursement prefilled from a suggested settlement on the balances screen.
    public init(
        settling reimbursement: Reimbursement,
        group: Group,
        title: String,
        locale: Locale = .autoupdatingCurrent
    ) {
        let digits = Self.minorUnitDigits(for: group, locale: locale)

        self.init(
            title: title,
            amountText: Self.text(
                forMinorUnits: reimbursement.amount, locale: locale, minorUnitDigits: digits
            ),
            categoryID: 1,  // "Payment"
            paidByID: reimbursement.from,
            splitMode: .evenly,
            participants: group.participants.map {
                ParticipantShareDraft(
                    id: $0.id, name: $0.name, isIncluded: $0.id == reimbursement.to
                )
            },
            isReimbursement: true,
            locale: locale,
            minorUnitDigits: digits,
            groupCurrencyCode: group.currencyCode,
            originalCurrencyCode: group.currencyCode
        )
    }

    // MARK: - Derived values

    /// The total in minor units, or nil if what was typed isn't a number.
    ///
    /// Under a conversion the total is not typed at all: it is what the amount paid comes to at
    /// the rate given, and deriving it here rather than copying it into `amountText` is what
    /// makes it impossible to store an expense whose rate does not produce its own amount.
    public var amountMinorUnits: Int? {
        if conversionRequired { return convertedAmountMinorUnits }
        return MoneyFormatter.minorUnits(
            from: amountText, locale: locale, minorUnitDigits: minorUnitDigits
        )
    }

    // MARK: Currency conversion

    /// Whether this expense was paid in a currency the group is not denominated in.
    ///
    /// Both sides have to be real ISO codes. A group with only a free-text symbol has nothing to
    /// convert *to* — that is the one case where the feature is unavailable rather than unused,
    /// and the group form is where it gets explained.
    public var conversionRequired: Bool {
        guard let group = Self.isoCode(groupCurrencyCode),
              let original = Self.isoCode(originalCurrencyCode)
        else { return false }
        return group != original
    }

    /// Digits in the minor unit of what was actually paid, which is not the group's: a €40.00
    /// dinner charged to a yen group is 4000 in one field and ¥6,540 in the other.
    public var originalMinorUnitDigits: Int {
        MoneyFormatter.minorUnitDigits(forCurrencyCode: originalCurrencyCode, locale: locale)
    }

    /// What was paid, in the minor units of the currency it was paid in.
    public var originalAmountMinorUnits: Int? {
        MoneyFormatter.minorUnits(
            from: originalAmountText, locale: locale, minorUnitDigits: originalMinorUnitDigits
        )
    }

    public var conversionRate: Decimal? {
        MoneyFormatter.number(from: conversionRateText, locale: locale)
    }

    /// What the amount paid comes to in the group's currency, in its minor units.
    public var convertedAmountMinorUnits: Int? {
        guard conversionRequired,
              let paid = originalAmountMinorUnits,
              let rate = conversionRate
        else { return nil }

        let paidInMajorUnits = Decimal(paid) / pow(Decimal(10), originalMinorUnitDigits)
        return MoneyFormatter.roundToInteger(
            paidInMajorUnits * rate * pow(Decimal(10), minorUnitDigits)
        )
    }

    /// Changing what the expense was paid in.
    ///
    /// Coming back to the group's own currency carries the converted total into the amount
    /// field, so the expense keeps the value it was showing rather than snapping back to
    /// whatever had been typed before the conversion.
    public mutating func useCurrency(_ code: String?) {
        let converted = convertedAmountMinorUnits
        let isADifferentCurrency = Self.isoCode(code) != Self.isoCode(originalCurrencyCode)
        originalCurrencyCode = code

        if isADifferentCurrency {
            // A rate belongs to a pair of currencies, so it cannot come along to another pair —
            // whether it was looked up or typed. The amount paid does stay: it is what was on
            // the receipt, and a currency picked by mistake should not cost it.
            conversionRateText = ""
        }
        if !conversionRequired, let converted {
            amountText = Self.text(
                forMinorUnits: converted, locale: locale, minorUnitDigits: minorUnitDigits
            )
        }
    }

    /// Takes a looked-up rate as the one to use.
    public mutating func use(rate: Decimal) {
        conversionRateText = Self.text(forRate: rate, locale: locale)
    }

    public var includedParticipants: [ParticipantShareDraft] {
        participants.filter(\.isIncluded)
    }

    /// Whether keeping this split for the group's later expenses is worth offering.
    ///
    /// A reimbursement is one person handing money to one other, and never the shape of the
    /// group's ordinary expenses: remembering it would leave every expense after it paid for by
    /// whoever happened to be owed.
    public var isSplitWorthRemembering: Bool { !isReimbursement }

    /// Whether the split covers the whole group, which is what decides whether the paid-for list
    /// offers to select all or to select none.
    public var allParticipantsIncluded: Bool {
        !participants.isEmpty && participants.allSatisfy(\.isIncluded)
    }

    /// Puts the whole group in the split, or takes it all out — whichever the selection isn't.
    ///
    /// Everyone keeps the share they were last given, since the rows stay in `participants`
    /// either way: a value typed before an unintended "select none" comes back with its owner.
    public mutating func setAllParticipantsIncluded(_ isIncluded: Bool) {
        for index in participants.indices {
            participants[index].isIncluded = isIncluded
        }
    }

    /// What each included participant's `shares` field should be sent as.
    ///
    /// The server stores this verbatim, and its meaning changes with the split mode: a share
    /// count or percentage scaled by 100, or — for `.byAmount` — a raw minor-unit amount.
    public func shareValue(for participant: ParticipantShareDraft) -> Int? {
        switch splitMode {
        case .evenly:
            100
        case .byShares, .byPercentage:
            // Scaled by 100 by the protocol, not by the currency: two shares are 200 even in a
            // group that counts in whole yen.
            MoneyFormatter.minorUnits(from: participant.valueText, locale: locale)
        case .byAmount:
            MoneyFormatter.minorUnits(
                from: participant.valueText, locale: locale, minorUnitDigits: minorUnitDigits
            )
        }
    }

    /// For `.byAmount`, how far the shares are from the total; for `.byPercentage`, from 100%.
    /// Positive means there is more to allocate.
    public var unallocated: Int? {
        let allocated = includedParticipants.reduce(into: 0) { total, participant in
            total += shareValue(for: participant) ?? 0
        }
        switch splitMode {
        case .byAmount:
            guard let amount = amountMinorUnits else { return nil }
            return amount - allocated
        case .byPercentage:
            return 10_000 - allocated
        case .evenly, .byShares:
            return nil
        }
    }

    // MARK: - Validation

    public enum Problem: Equatable, Sendable {
        case titleTooShort
        case amountMissing
        case amountNotANumber
        case amountZero
        case amountTooLarge
        case originalAmountMissing
        case originalAmountNotANumber
        case originalAmountZero
        case originalAmountTooLarge
        case conversionRateMissing
        case conversionRateNotANumber
        case conversionRateNotPositive
        case payerMissing
        case noParticipantsSelected
        case shareNotANumber(ParticipantShareDraft.ID)
        case shareNotPositive(ParticipantShareDraft.ID)
        /// Shares must add up to the expense total. `difference` is what's left to allocate.
        case amountsDoNotSumToTotal(difference: Int)
        /// Percentages must add up to 100. `difference` is in hundredths of a percent.
        case percentagesDoNotSumTo100(difference: Int)
    }

    public var problems: [Problem] {
        var problems: [Problem] = []

        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            problems.append(.titleTooShort)
        }

        if conversionRequired {
            // The total is derived from these two, so they are what there is to get wrong — and
            // the total is still worth checking afterwards, since a small enough rate rounds a
            // real payment down to nothing.
            problems.append(contentsOf: conversionProblems)
            if let amount = amountMinorUnits {
                if amount == 0 { problems.append(.amountZero) }
                if amount > 10_000_000_00 { problems.append(.amountTooLarge) }
            }
        } else if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(.amountMissing)
        } else if let amount = amountMinorUnits {
            if amount == 0 { problems.append(.amountZero) }
            if amount > 10_000_000_00 { problems.append(.amountTooLarge) }
        } else {
            problems.append(.amountNotANumber)
        }

        if paidByID == nil { problems.append(.payerMissing) }

        let included = includedParticipants
        if included.isEmpty { problems.append(.noParticipantsSelected) }

        if splitMode != .evenly {
            for participant in included {
                guard let value = shareValue(for: participant) else {
                    problems.append(.shareNotANumber(participant.id))
                    continue
                }
                if value <= 0 { problems.append(.shareNotPositive(participant.id)) }
            }
        }

        // Only worth checking the totals once every individual share is a usable number.
        let sharesAreUsable = !problems.contains {
            if case .shareNotANumber = $0 { return true }
            if case .shareNotPositive = $0 { return true }
            return false
        }

        if sharesAreUsable, !included.isEmpty, let difference = unallocated, difference != 0 {
            switch splitMode {
            case .byAmount:
                if amountMinorUnits != nil {
                    problems.append(.amountsDoNotSumToTotal(difference: difference))
                }
            case .byPercentage:
                problems.append(.percentagesDoNotSumTo100(difference: difference))
            case .evenly, .byShares:
                break
            }
        }

        return problems
    }

    private var conversionProblems: [Problem] {
        var problems: [Problem] = []

        if originalAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(.originalAmountMissing)
        } else if let paid = originalAmountMinorUnits {
            if paid == 0 { problems.append(.originalAmountZero) }
            if paid > 10_000_000_00 { problems.append(.originalAmountTooLarge) }
        } else {
            problems.append(.originalAmountNotANumber)
        }

        if conversionRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(.conversionRateMissing)
        } else if let rate = conversionRate {
            if rate <= 0 { problems.append(.conversionRateNotPositive) }
        } else {
            problems.append(.conversionRateNotANumber)
        }

        return problems
    }

    public var isValid: Bool { problems.isEmpty }

    public func problems(forParticipant id: ParticipantShareDraft.ID) -> [Problem] {
        problems.filter {
            switch $0 {
            case .shareNotANumber(let target), .shareNotPositive(let target):
                target == id
            default:
                false
            }
        }
    }

    // MARK: - Submission

    /// The payload to send, or nil if the draft isn't valid.
    public var formValues: ExpenseFormValues? {
        guard isValid, let amount = amountMinorUnits, let paidByID else { return nil }

        let paidFor: [ExpenseFormValues.PaidFor] = includedParticipants.compactMap { participant in
            guard let shares = shareValue(for: participant) else { return nil }
            return .init(participant: participant.id, shares: shares)
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return ExpenseFormValues(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            expenseDate: expenseDate,
            amount: amount,
            category: categoryID,
            paidBy: paidByID,
            paidFor: paidFor,
            splitMode: splitMode,
            // Sent because the web app sends it, and read by neither: the procedures ignore it,
            // and the browser that set it is the only thing that ever acts on it. What remembers
            // a split here is the phone — see `DefaultSplit`.
            saveDefaultSplittingOptions: saveSplitAsDefault,
            isReimbursement: isReimbursement,
            documents: documents,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            recurrenceRule: recurrenceRule,
            // Sent as nulls when there is no conversion, which is what clears them on an expense
            // that used to have one. See `ExpenseFormValues.encode(to:)`.
            originalAmount: conversionRequired ? originalAmountMinorUnits : nil,
            originalCurrency: conversionRequired ? Self.isoCode(originalCurrencyCode) : nil,
            conversionRate: conversionRequired ? conversionRate : nil
        )
    }

    // MARK: - Text conversion

    /// How many digits the group's currency keeps, for a draft being built from one.
    static func minorUnitDigits(for group: Group, locale: Locale) -> Int {
        MoneyFormatter.minorUnitDigits(forCurrencyCode: group.currencyCode, locale: locale)
    }

    /// A currency code that is worth acting on: three letters, upper case, or nothing.
    static func isoCode(_ code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.count == 3
        else { return nil }
        return code
    }

    /// A rate is shown at the precision it arrived with, up to six places — enough for the
    /// currencies quoted in thousands to a euro — and never grouped, since the field it lands in
    /// is parsed back as a plain number.
    public static func text(forRate rate: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        rate.formatted(
            .number.precision(.fractionLength(0...6)).grouping(.never).locale(locale)
        )
    }

    static func text(forMinorUnits value: Int, locale: Locale, minorUnitDigits: Int = 2) -> String {
        MoneyFormatter(minorUnitDigits: minorUnitDigits, locale: locale)
            .plainString(minorUnits: value)
    }

    /// Turns a stored `shares` value back into something to show in the field it came from.
    static func text(
        forShares shares: Int,
        splitMode: SplitMode,
        locale: Locale,
        minorUnitDigits: Int = 2
    ) -> String {
        switch splitMode {
        case .byAmount:
            // Already a minor-unit amount, in the group's own currency.
            text(forMinorUnits: shares, locale: locale, minorUnitDigits: minorUnitDigits)
        case .evenly, .byShares, .byPercentage:
            // Scaled by 100 whatever the currency; show whole numbers without a pointless ".00".
            shares % 100 == 0
                ? String(shares / 100)
                : text(forMinorUnits: shares, locale: locale)
        }
    }
}

extension ExpenseFormDraft.Problem {
    /// Wording follows the web app's error messages so the two don't drift apart.
    public var message: String {
        switch self {
        case .titleTooShort:
            String(localized: "Enter at least two characters.", bundle: Bundle.module)
        case .amountMissing:
            String(localized: "You must enter an amount.", bundle: Bundle.module)
        case .amountNotANumber:
            String(localized: "Invalid number.", bundle: Bundle.module)
        case .amountZero:
            String(localized: "The amount must not be zero.", bundle: Bundle.module)
        case .amountTooLarge:
            String(localized: "The amount must be lower than 10,000,000.", bundle: Bundle.module)
        case .originalAmountMissing:
            String(localized: "Enter what was actually paid.", bundle: Bundle.module)
        case .originalAmountNotANumber:
            String(localized: "Invalid number.", bundle: Bundle.module)
        case .originalAmountZero:
            String(localized: "The amount must not be zero.", bundle: Bundle.module)
        case .originalAmountTooLarge:
            String(localized: "The amount must be lower than 10,000,000.", bundle: Bundle.module)
        case .conversionRateMissing:
            String(localized: "Enter an exchange rate.", bundle: Bundle.module)
        case .conversionRateNotANumber:
            String(localized: "Invalid number.", bundle: Bundle.module)
        case .conversionRateNotPositive:
            String(localized: "The rate must be strictly greater than zero.", bundle: Bundle.module)
        case .payerMissing:
            String(localized: "You must select a participant.", bundle: Bundle.module)
        case .noParticipantsSelected:
            String(localized: "The expense must be paid for at least one participant.", bundle: Bundle.module)
        case .shareNotANumber:
            String(localized: "Invalid number.", bundle: Bundle.module)
        case .shareNotPositive:
            String(localized: "All shares must be higher than 0.", bundle: Bundle.module)
        case .amountsDoNotSumToTotal:
            String(localized: "Sum of amounts must equal the expense amount.", bundle: Bundle.module)
        case .percentagesDoNotSumTo100:
            String(localized: "Sum of percentages must equal 100.", bundle: Bundle.module)
        }
    }
}
