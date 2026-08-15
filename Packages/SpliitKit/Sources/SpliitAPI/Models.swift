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
        recurrenceRule: RecurrenceRule = .never
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
    }
}
