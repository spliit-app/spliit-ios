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

    public init(
        title: String = "",
        expenseDate: Date = .now,
        amountText: String = "",
        categoryID: Int = 0,
        paidByID: String? = nil,
        splitMode: SplitMode = .evenly,
        participants: [ParticipantShareDraft] = [],
        isReimbursement: Bool = false,
        notes: String = "",
        locale: Locale = .autoupdatingCurrent,
        minorUnitDigits: Int = 2,
        recurrenceRule: RecurrenceRule = .never,
        documents: [ExpenseDocument] = []
    ) {
        self.title = title
        self.expenseDate = expenseDate
        self.amountText = amountText
        self.categoryID = categoryID
        self.paidByID = paidByID
        self.splitMode = splitMode
        self.participants = participants
        self.isReimbursement = isReimbursement
        self.notes = notes
        self.locale = locale
        self.minorUnitDigits = minorUnitDigits
        self.recurrenceRule = recurrenceRule
        self.documents = documents
    }

    /// A blank expense for a group: everyone included, split evenly.
    ///
    /// - Parameter paidBy: whoever the user said they are in this group, when they have said.
    ///   An ID the group no longer has falls back to the first participant, which is what this
    ///   form filled in before anybody could answer the question.
    public init(
        creatingIn group: Group,
        paidBy: String? = nil,
        locale: Locale = .autoupdatingCurrent
    ) {
        let payer = group.participants.first { $0.id == paidBy } ?? group.participants.first
        self.init(
            paidByID: payer?.id,
            participants: group.participants.map {
                ParticipantShareDraft(id: $0.id, name: $0.name, isIncluded: true)
            },
            locale: locale,
            minorUnitDigits: Self.minorUnitDigits(for: group, locale: locale)
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
            documents: expense.documents
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
            minorUnitDigits: digits
        )
    }

    // MARK: - Derived values

    /// The total in minor units, or nil if what was typed isn't a number.
    public var amountMinorUnits: Int? {
        MoneyFormatter.minorUnits(from: amountText, locale: locale, minorUnitDigits: minorUnitDigits)
    }

    public var includedParticipants: [ParticipantShareDraft] {
        participants.filter(\.isIncluded)
    }

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

        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            saveDefaultSplittingOptions: false,
            isReimbursement: isReimbursement,
            documents: documents,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            recurrenceRule: recurrenceRule
        )
    }

    // MARK: - Text conversion

    /// How many digits the group's currency keeps, for a draft being built from one.
    static func minorUnitDigits(for group: Group, locale: Locale) -> Int {
        MoneyFormatter.minorUnitDigits(forCurrencyCode: group.currencyCode, locale: locale)
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
