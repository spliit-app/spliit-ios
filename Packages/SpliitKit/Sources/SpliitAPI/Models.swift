import Foundation

// Money crosses the wire as an integer count of minor units: `amount == 1234` is 12.34.
// This holds for expense amounts, balances and reimbursements alike.

public struct ExpenseCategory: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    /// The heading this category sits under in the picker, e.g. "Food and Drink".
    public let grouping: String
    public let name: String

    public init(id: Int, grouping: String, name: String) {
        self.id = id
        self.grouping = grouping
        self.name = name
    }
}

public struct Participant: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Group: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let information: String?
    /// A free-text symbol such as "$" or "CHF" — not an ISO code. See `currencyCode`.
    public let currency: String
    /// ISO-4217, when the group has one. Older groups only have a symbol.
    public let currencyCode: String?
    public let createdAt: Date
    public let participants: [Participant]

    public init(
        id: String,
        name: String,
        information: String?,
        currency: String,
        currencyCode: String?,
        createdAt: Date,
        participants: [Participant]
    ) {
        self.id = id
        self.name = name
        self.information = information
        self.currency = currency
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.participants = participants
    }
}

/// A group as `groups.list` returns it: no participants, only how many.
public struct GroupSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let currency: String
    public let createdAt: Date
    public let participantCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, currency, createdAt
        case count = "_count"
    }

    private struct Counts: Decodable {
        let participants: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        currency = try container.decode(String.self, forKey: .currency)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        participantCount = try container.decode(Counts.self, forKey: .count).participants
    }

    public init(id: String, name: String, currency: String, createdAt: Date, participantCount: Int) {
        self.id = id
        self.name = name
        self.currency = currency
        self.createdAt = createdAt
        self.participantCount = participantCount
    }
}

public enum SplitMode: String, Codable, Sendable, CaseIterable {
    case evenly = "EVENLY"
    case byShares = "BY_SHARES"
    case byPercentage = "BY_PERCENTAGE"
    case byAmount = "BY_AMOUNT"
}

public enum RecurrenceRule: String, Codable, Sendable, CaseIterable {
    case never = "NONE"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"

    /// Whether this rule actually schedules anything.
    public var repeats: Bool { self != .never }
}

/// Where the server has got to with a recurring expense: when the next one in the series is
/// due, and whether it has been made yet.
///
/// Exactly one of these hangs off each expense in a series. When the server creates the next
/// expense it stamps `nextExpenseCreatedAt` on this one and gives the new expense a fresh,
/// unstamped link of its own — so a stamped link means the series has moved on and this expense
/// no longer steers it.
///
/// That distinction is not cosmetic. `groups.expenses.update` will only create, move or remove
/// a schedule while the link is unstamped; against a stamped one it writes the `recurrenceRule`
/// column and changes nothing that is actually scheduled. Turning recurrence off on last
/// month's rent does not stop next month's.
public struct RecurringExpenseLink: Decodable, Sendable, Hashable {
    public let id: String
    /// The date the next expense in the series will carry. The server creates it lazily — the
    /// first time anyone lists the group's expenses on or after this date — so a date in the
    /// past means one is owed rather than one was missed.
    public let nextExpenseDate: Date
    /// When the next expense was actually created, and nil while it is still pending.
    public let nextExpenseCreatedAt: Date?

    public init(id: String, nextExpenseDate: Date, nextExpenseCreatedAt: Date? = nil) {
        self.id = id
        self.nextExpenseDate = nextExpenseDate
        self.nextExpenseCreatedAt = nextExpenseCreatedAt
    }

    /// Whether this expense is still the one deciding what the series does next.
    public var isPending: Bool { nextExpenseCreatedAt == nil }
}

public struct ExpenseDocument: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let url: String
    public let width: Int
    public let height: Int

    public init(id: String, url: String, width: Int, height: Int) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
    }
}

/// A `Prisma.Decimal` crosses superjson as a string; be lenient in case an instance sends a
/// number instead.
public struct LenientDecimal: Codable, Sendable, Hashable {
    public let value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), let parsed = Decimal(string: text) {
            value = parsed
        } else if let number = try? container.decode(Double.self) {
            value = Decimal(number)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal as a string or number."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }
}

/// An expense as it appears in a group's list. Carries only what the row needs; use
/// `ExpenseDetails` to edit one.
public struct ExpenseListItem: Decodable, Sendable, Identifiable, Hashable {
    public struct PaidFor: Decodable, Sendable, Hashable {
        public let participant: Participant
        public let shares: Int
    }

    public let id: String
    public let title: String
    /// Minor units.
    public let amount: Int
    public let createdAt: Date
    public let expenseDate: Date
    public let isReimbursement: Bool
    public let splitMode: SplitMode
    public let recurrenceRule: RecurrenceRule?
    public let category: ExpenseCategory?
    public let paidBy: Participant
    public let paidFor: [PaidFor]
    public let documentCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, createdAt, expenseDate, isReimbursement
        case splitMode, recurrenceRule, category, paidBy, paidFor
        case count = "_count"
    }

    private struct Counts: Decodable {
        let documents: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Int.self, forKey: .amount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expenseDate = try container.decode(Date.self, forKey: .expenseDate)
        isReimbursement = try container.decode(Bool.self, forKey: .isReimbursement)
        splitMode = try container.decode(SplitMode.self, forKey: .splitMode)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
        category = try container.decodeIfPresent(ExpenseCategory.self, forKey: .category)
        paidBy = try container.decode(Participant.self, forKey: .paidBy)
        paidFor = try container.decode([PaidFor].self, forKey: .paidFor)
        documentCount = try container.decodeIfPresent(Counts.self, forKey: .count)?.documents ?? 0
    }

    /// For building one without a server — what the totals-by-category fold is tested against.
    /// Everything the wire sends but nothing it needs, so a test can name the two fields it
    /// cares about and leave the rest alone.
    public init(
        id: String,
        title: String,
        amount: Int,
        createdAt: Date = .distantPast,
        expenseDate: Date = .distantPast,
        isReimbursement: Bool = false,
        splitMode: SplitMode = .evenly,
        recurrenceRule: RecurrenceRule? = nil,
        category: ExpenseCategory? = nil,
        paidBy: Participant = Participant(id: "", name: ""),
        paidFor: [PaidFor] = [],
        documentCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.createdAt = createdAt
        self.expenseDate = expenseDate
        self.isReimbursement = isReimbursement
        self.splitMode = splitMode
        self.recurrenceRule = recurrenceRule
        self.category = category
        self.paidBy = paidBy
        self.paidFor = paidFor
        self.documentCount = documentCount
    }
}

/// Everything needed to render and edit a single expense.
public struct ExpenseDetails: Decodable, Sendable, Identifiable, Hashable {
    public struct PaidFor: Decodable, Sendable, Hashable {
        public let participantId: String
        /// For `.evenly`, `.byShares` and `.byPercentage` this is the share value ×100.
        /// For `.byAmount` it is a raw minor-unit amount. See `ExpenseFormValues`.
        public let shares: Int

        public init(participantId: String, shares: Int) {
            self.participantId = participantId
            self.shares = shares
        }
    }

    public let id: String
    public let groupId: String
    public let title: String
    /// Minor units.
    public let amount: Int
    public let categoryId: Int
    public let category: ExpenseCategory?
    public let expenseDate: Date
    public let createdAt: Date
    public let paidById: String
    public let paidBy: Participant
    public let paidFor: [PaidFor]
    public let isReimbursement: Bool
    public let splitMode: SplitMode
    public let notes: String?
    public let documents: [ExpenseDocument]
    public let recurrenceRule: RecurrenceRule?
    /// Where the series this expense belongs to has got to, when it is in one. Nil for an
    /// expense that has never had a recurrence.
    public let recurringExpenseLink: RecurringExpenseLink?
    public let originalAmount: Int?
    public let originalCurrency: String?
    public let conversionRate: LenientDecimal?

    public init(
        id: String,
        groupId: String,
        title: String,
        amount: Int,
        categoryId: Int,
        category: ExpenseCategory?,
        expenseDate: Date,
        createdAt: Date,
        paidById: String,
        paidBy: Participant,
        paidFor: [PaidFor],
        isReimbursement: Bool,
        splitMode: SplitMode,
        notes: String?,
        documents: [ExpenseDocument],
        recurrenceRule: RecurrenceRule?,
        recurringExpenseLink: RecurringExpenseLink? = nil,
        originalAmount: Int?,
        originalCurrency: String?,
        conversionRate: LenientDecimal?
    ) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.amount = amount
        self.categoryId = categoryId
        self.category = category
        self.expenseDate = expenseDate
        self.createdAt = createdAt
        self.paidById = paidById
        self.paidBy = paidBy
        self.paidFor = paidFor
        self.isReimbursement = isReimbursement
        self.splitMode = splitMode
        self.notes = notes
        self.documents = documents
        self.recurrenceRule = recurrenceRule
        self.recurringExpenseLink = recurringExpenseLink
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.conversionRate = conversionRate
    }
}

public struct Balance: Decodable, Sendable, Hashable {
    /// Minor units.
    public let paid: Int
    /// Minor units.
    public let paidFor: Int
    /// `paid - paidFor`, in minor units. Negative means this participant owes.
    public let total: Int

    public init(paid: Int, paidFor: Int, total: Int) {
        self.paid = paid
        self.paidFor = paidFor
        self.total = total
    }
}

public struct Reimbursement: Decodable, Sendable, Hashable {
    /// Participant ID of whoever owes.
    public let from: String
    /// Participant ID of whoever is owed.
    public let to: String
    /// Minor units.
    public let amount: Int

    public init(from: String, to: String, amount: Int) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

// MARK: - Activity

/// What a recorded activity was.
///
/// Unknown values decode instead of throwing, which `SplitMode` deliberately does not: a split
/// mode this client cannot read is money it would divide wrongly, while an activity it cannot
/// read is one line of prose. A server that grows a fifth kind should cost the log a row, not
/// the whole tab.
public enum ActivityType: Decodable, Sendable, Hashable {
    case updateGroup
    case createExpense
    case updateExpense
    case deleteExpense
    /// Something this version has no sentence for.
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "UPDATE_GROUP": self = .updateGroup
        case "CREATE_EXPENSE": self = .createExpense
        case "UPDATE_EXPENSE": self = .updateExpense
        case "DELETE_EXPENSE": self = .deleteExpense
        case let other: self = .unknown(other)
        }
    }

    /// False for a kind this version cannot describe, and so should not draw a row for.
    public var isRecognised: Bool {
        if case .unknown = self { return false }
        return true
    }
}

/// One thing that happened to a group, as `groups.activities.list` records it.
public struct Activity: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let groupId: String
    public let time: Date
    public let activityType: ActivityType

    /// Who did it — but only when the client that did it said so. The four mutating procedures
    /// take a `participantId` and none of them requires it, so this is nil for anything written
    /// by the web app before someone identified themselves, and for every expense this app wrote
    /// before it started sending one.
    public let participantId: String?

    public let expenseId: String?

    /// The expense's title **as it was** when this was recorded, which is the point: renaming an
    /// expense leaves the old name on the line that describes it being created. The server calls
    /// this column `data`; it has never held anything else.
    public let title: String?

    /// Whether the expense this refers to is still in the group. The server sends the whole
    /// expense alongside; all a log row does with it is decide whether it can be opened, and
    /// decoding a second copy of a model we already have would only be one more thing to keep in
    /// step with the schema.
    public let expenseStillExists: Bool

    private enum CodingKeys: String, CodingKey {
        case id, groupId, time, activityType, participantId, expenseId, expense
        case data
    }

    private struct ExpenseReference: Decodable {
        let id: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupId = try container.decode(String.self, forKey: .groupId)
        time = try container.decode(Date.self, forKey: .time)
        activityType = try container.decode(ActivityType.self, forKey: .activityType)
        participantId = try container.decodeIfPresent(String.self, forKey: .participantId)
        expenseId = try container.decodeIfPresent(String.self, forKey: .expenseId)
        title = try container.decodeIfPresent(String.self, forKey: .data)
        expenseStillExists =
            try container.decodeIfPresent(ExpenseReference.self, forKey: .expense) != nil
    }

    public init(
        id: String,
        groupId: String,
        time: Date,
        activityType: ActivityType,
        participantId: String? = nil,
        expenseId: String? = nil,
        title: String? = nil,
        expenseStillExists: Bool = false
    ) {
        self.id = id
        self.groupId = groupId
        self.time = time
        self.activityType = activityType
        self.participantId = participantId
        self.expenseId = expenseId
        self.title = title
        self.expenseStillExists = expenseStillExists
    }
}

// MARK: - Form values

public struct GroupFormValues: Encodable, Sendable {
    public struct Participant: Encodable, Sendable {
        /// Omitted for participants being added.
        public let id: String?
        public let name: String

        public init(id: String? = nil, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let name: String
    public let information: String?
    public let currency: String
    public let currencyCode: String?
    public let participants: [Participant]

    public init(
        name: String,
        information: String? = nil,
        currency: String,
        currencyCode: String? = nil,
        participants: [Participant]
    ) {
        self.name = name
        self.information = information
        self.currency = currency
        self.currencyCode = currencyCode
        self.participants = participants
    }
}

public struct ExpenseFormValues: Encodable, Sendable {
    public struct PaidFor: Encodable, Sendable {
        public let participant: String
        /// The server stores this verbatim. For `.evenly`, `.byShares` and `.byPercentage`
        /// it is the share value ×100 (so 1 share is `100`, 33.5% is `3350`); for
        /// `.byAmount` it is a minor-unit amount that must sum to `amount`.
        public let shares: Int

        public init(participant: String, shares: Int) {
            self.participant = participant
            self.shares = shares
        }
    }

    public let title: String
    public let expenseDate: Date
    /// Minor units. The server writes this straight to the database.
    public let amount: Int
    /// ExpenseCategory ID; 0 is "General".
    public let category: Int
    public let paidBy: String
    public let paidFor: [PaidFor]
    public let splitMode: SplitMode
    public let saveDefaultSplittingOptions: Bool
    public let isReimbursement: Bool
    public let documents: [ExpenseDocument]
    public let notes: String?
    public let recurrenceRule: RecurrenceRule
    /// What was actually paid, in `originalCurrency`'s own minor units, when the expense was in
    /// a currency the group is not denominated in. Nil when it was in the group's currency.
    public let originalAmount: Int?
    /// ISO-4217 of what was actually paid. Nil when the expense was in the group's currency.
    public let originalCurrency: String?
    /// `amount` ÷ `originalAmount`: one unit of `originalCurrency` in the group's currency.
    public let conversionRate: Decimal?

    public init(
        title: String,
        expenseDate: Date,
        amount: Int,
        category: Int = 0,
        paidBy: String,
        paidFor: [PaidFor],
        splitMode: SplitMode = .evenly,
        saveDefaultSplittingOptions: Bool = false,
        isReimbursement: Bool = false,
        documents: [ExpenseDocument] = [],
        notes: String? = nil,
        recurrenceRule: RecurrenceRule = .never,
        originalAmount: Int? = nil,
        originalCurrency: String? = nil,
        conversionRate: Decimal? = nil
    ) {
        self.title = title
        self.expenseDate = expenseDate
        self.amount = amount
        self.category = category
        self.paidBy = paidBy
        self.paidFor = paidFor
        self.splitMode = splitMode
        self.saveDefaultSplittingOptions = saveDefaultSplittingOptions
        self.isReimbursement = isReimbursement
        self.documents = documents
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.conversionRate = conversionRate
    }

    private enum CodingKeys: String, CodingKey {
        case title, expenseDate, amount, category, paidBy, paidFor, splitMode
        case saveDefaultSplittingOptions, isReimbursement, documents, notes, recurrenceRule
        case originalAmount, originalCurrency, conversionRate
    }

    /// Spelled out rather than synthesised, for `originalCurrency` alone: it is written even when
    /// nil, as JSON null.
    ///
    /// `encodeIfPresent` — what Swift synthesises — would drop it from the request, the server
    /// would read `undefined`, and Prisma would leave the column exactly as it was. An expense
    /// moved back to the group's own currency would go on claiming to have been paid in another.
    ///
    /// The amount and the rate cannot be cleared the same way, and are omitted instead: the
    /// server's schema accepts a number, a numeric string or `''` for them, and rejects null
    /// outright — `make test-live` is what proved it. Whatever they were stays in the database,
    /// inert: `originalCurrency` is what says an expense was paid in another currency, and
    /// nothing reads the other two without it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(expenseDate, forKey: .expenseDate)
        try container.encode(amount, forKey: .amount)
        try container.encode(category, forKey: .category)
        try container.encode(paidBy, forKey: .paidBy)
        try container.encode(paidFor, forKey: .paidFor)
        try container.encode(splitMode, forKey: .splitMode)
        try container.encode(saveDefaultSplittingOptions, forKey: .saveDefaultSplittingOptions)
        try container.encode(isReimbursement, forKey: .isReimbursement)
        try container.encode(documents, forKey: .documents)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(originalCurrency, forKey: .originalCurrency)
        try container.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try container.encodeIfPresent(conversionRate, forKey: .conversionRate)
    }
}
