import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Group form")
struct GroupFormDraftTests {

    private func draft(
        name: String = "Weekend in Lisbon",
        currency: String = "€",
        participants: [String] = ["Ana", "Bruno"]
    ) -> GroupFormDraft {
        GroupFormDraft(
            name: name,
            currency: currency,
            participants: participants.map { ParticipantDraft(name: $0) }
        )
    }

    @Test("A complete group is valid")
    func acceptsCompleteGroup() {
        #expect(draft().isValid)
    }

    @Test("The name must be between 2 and 50 characters")
    func validatesName() {
        #expect(draft(name: "A").problems.contains(.nameTooShort))
        #expect(draft(name: "  A  ").problems.contains(.nameTooShort))
        #expect(draft(name: String(repeating: "a", count: 51)).problems.contains(.nameTooLong))
        #expect(draft(name: String(repeating: "a", count: 50)).isValid)
    }

    @Test("The currency symbol must be between 1 and 5 characters")
    func validatesCurrency() {
        #expect(draft(currency: "").problems.contains(.currencyMissing))
        #expect(draft(currency: "   ").problems.contains(.currencyMissing))
        #expect(draft(currency: "ABCDEF").problems.contains(.currencyTooLong))
        #expect(draft(currency: "CHF").isValid)
    }

    @Test("A group needs at least one participant")
    func requiresParticipants() {
        #expect(draft(participants: []).problems.contains(.noParticipants))
    }

    @Test("Participant names follow the same length rules")
    func validatesParticipantNames() {
        let form = draft(participants: ["A", "Bruno"])
        let target = form.participants[0].id

        #expect(form.problems.contains(.participantNameTooShort(target)))
        #expect(form.problems(forParticipant: target).count == 1)
        #expect(form.problems(forParticipant: form.participants[1].id).isEmpty)
    }

    /// The server flags the later of a duplicate pair, so errors land where a user expects.
    @Test("A duplicate name is flagged on the second occurrence only")
    func rejectsDuplicateNames() {
        let form = draft(participants: ["Ana", "Bruno", "Ana"])

        #expect(form.problems.contains(.duplicateParticipantName(form.participants[2].id)))
        #expect(form.problems(forParticipant: form.participants[0].id).isEmpty)
    }

    @Test("Names differing only by surrounding spaces still count as duplicates")
    func treatsPaddedNamesAsDuplicates() {
        let form = draft(participants: ["Ana", "  Ana  "])

        #expect(form.problems.contains(.duplicateParticipantName(form.participants[1].id)))
    }

    @Test("Submitted values are trimmed, and blank information is omitted")
    func buildsFormValues() throws {
        var form = draft(name: "  Lisbon trip  ", participants: ["  Ana  ", "Bruno"])
        form.information = "   "

        let values = form.formValues

        #expect(values.name == "Lisbon trip")
        #expect(values.participants.map(\.name) == ["Ana", "Bruno"])
        #expect(values.information == nil)
    }

    @Test("Editing an existing group keeps participant IDs and the ISO currency code")
    func preservesServerIdentity() throws {
        let group = Group(
            id: "g1",
            name: "Flat 3B",
            information: "Rent and bills",
            currency: "$",
            currencyCode: "USD",
            createdAt: .now,
            participants: [.init(id: "p1", name: "Dana"), .init(id: "p2", name: "Eli")]
        )

        var form = GroupFormDraft(editing: group)
        form.participants.append(ParticipantDraft(name: "Fen"))
        let values = form.formValues

        #expect(values.currencyCode == "USD")
        #expect(values.participants.map(\.id) == ["p1", "p2", nil])
        #expect(values.information == "Rent and bills")
    }

    // MARK: - Currency

    @Test("A new group starts in the currency the device is set to")
    func defaultsToTheDeviceCurrency() {
        let swiss = GroupFormDraft(newGroupIn: Locale(identifier: "de_CH"))
        #expect(swiss.currencyCode == "CHF")
        #expect(swiss.currency == "CHF")

        let american = GroupFormDraft(newGroupIn: Locale(identifier: "en_US"))
        #expect(american.currencyCode == "USD")
        #expect(american.currency == "$")
    }

    /// The symbol beside every amount and the code the amounts are in have to agree, so the
    /// picker sets both. Nothing else in the app writes the symbol.
    @Test("Picking a currency sets the symbol as well as the code")
    func picksACurrency() throws {
        var form = draft(currency: "$")
        form.use(try #require(Currency.named("CHF", in: Locale(identifier: "en_US"))))

        #expect(form.currencyCode == "CHF")
        #expect(form.currency == "CHF")
        #expect(form.formValues.currencyCode == "CHF")
        #expect(!form.usesCustomSymbol)
    }

    @Test("A custom symbol keeps the symbol and drops the code")
    func fallsBackToACustomSymbol() throws {
        var form = draft()
        form.use(try #require(Currency.named("EUR", in: Locale(identifier: "en_US"))))
        form.useCustomSymbol()

        #expect(form.usesCustomSymbol)
        #expect(form.currency == "€", "The symbol that was there stays, as something to edit.")
        #expect(
            form.formValues.currencyCode == "",
            "Empty, not nil: nil is omitted from the request and leaves the stored code alone."
        )
    }

    /// The web app writes an empty string where we write nil. A group that arrives with one is
    /// a group with no code, not a group with an invalid one.
    @Test("An empty code from the web is treated as no code at all")
    func treatsAnEmptyCodeAsNone() {
        var form = draft()
        form.currencyCode = ""

        #expect(form.usesCustomSymbol)
        #expect(form.isValid)
        #expect(form.formValues.currencyCode == "")
    }

    @Test("A code that isn't three letters is reported rather than sent")
    func rejectsAMalformedCode() {
        var form = draft()
        form.currencyCode = "DOLLARS"

        #expect(form.problems.contains(.currencyCodeInvalid))
    }
}

@Suite("Expense form")
struct ExpenseFormDraftTests {

    private let group = Group(
        id: "g1",
        name: "Weekend in Lisbon",
        information: nil,
        currency: "€",
        currencyCode: "EUR",
        createdAt: .now,
        participants: [
            .init(id: "ana", name: "Ana"),
            .init(id: "bruno", name: "Bruno"),
            .init(id: "chloe", name: "Chloé"),
        ]
    )

    private func draft(
        amount: String = "42.50",
        splitMode: SplitMode = .evenly,
        values: [String: String] = [:],
        included: [String] = ["ana", "bruno", "chloe"]
    ) -> ExpenseFormDraft {
        var form = ExpenseFormDraft(creatingIn: group, locale: Locale(identifier: "en_US"))
        form.title = "Airport taxi"
        form.amountText = amount
        form.splitMode = splitMode
        form.participants = form.participants.map {
            var participant = $0
            participant.isIncluded = included.contains($0.id)
            if let value = values[$0.id] { participant.valueText = value }
            return participant
        }
        return form
    }

    @Test("A blank expense starts with everyone included and split evenly")
    func startsWithEveryoneIncluded() {
        let form = ExpenseFormDraft(creatingIn: group)

        #expect(form.splitMode == .evenly)
        #expect(form.includedParticipants.count == 3)
        #expect(form.paidByID == "ana")
    }

    @Test("A complete expense is valid")
    func acceptsCompleteExpense() {
        #expect(draft().isValid)
    }

    @Test("The title must be at least two characters")
    func validatesTitle() {
        var form = draft()
        form.title = "a"

        #expect(form.problems.contains(.titleTooShort))
    }

    @Test("The amount must be present, numeric, non-zero and under ten million")
    func validatesAmount() {
        #expect(draft(amount: "").problems.contains(.amountMissing))
        #expect(draft(amount: "abc").problems.contains(.amountNotANumber))
        #expect(draft(amount: "0").problems.contains(.amountZero))
        #expect(draft(amount: "0.00").problems.contains(.amountZero))
        #expect(draft(amount: "10000000.01").problems.contains(.amountTooLarge))
        #expect(draft(amount: "10000000.00").isValid)
    }

    @Test("A payer and at least one participant are required")
    func validatesPeople() {
        var form = draft()
        form.paidByID = nil
        #expect(form.problems.contains(.payerMissing))

        #expect(draft(included: []).problems.contains(.noParticipantsSelected))
    }

    /// Splitting evenly sends one share each, regardless of what is in the value fields.
    @Test("Splitting evenly sends one share per participant")
    func buildsEvenSplit() throws {
        let values = try #require(draft().formValues)

        #expect(values.amount == 4250)
        #expect(values.splitMode == .evenly)
        #expect(values.paidFor.map(\.shares) == [100, 100, 100])
    }

    /// Share counts are scaled by 100 on the wire — two shares is `200`.
    @Test("Share counts are sent scaled by 100")
    func buildsShareSplit() throws {
        let form = draft(
            splitMode: .byShares,
            values: ["ana": "1", "bruno": "1", "chloe": "2"]
        )
        let values = try #require(form.formValues)

        #expect(values.paidFor.map(\.shares) == [100, 100, 200])
    }

    @Test("Percentages are sent scaled by 100 and must total 100%")
    func validatesPercentageSplit() throws {
        let balanced = draft(
            splitMode: .byPercentage,
            values: ["ana": "50", "bruno": "30", "chloe": "20"]
        )
        #expect(balanced.isValid)
        #expect(try #require(balanced.formValues).paidFor.map(\.shares) == [5000, 3000, 2000])

        let short = draft(
            splitMode: .byPercentage,
            values: ["ana": "50", "bruno": "30", "chloe": "10"]
        )
        #expect(short.problems.contains(.percentagesDoNotSumTo100(difference: 1000)))
        #expect(short.unallocated == 1000)
    }

    /// For `.byAmount` the shares are raw minor units, not scaled — the one place the meaning
    /// of the field changes.
    @Test("Amounts are sent as minor units and must total the expense")
    func validatesAmountSplit() throws {
        let balanced = draft(
            amount: "30.00",
            splitMode: .byAmount,
            values: ["ana": "10.00", "bruno": "10.00", "chloe": "10.00"]
        )
        #expect(balanced.isValid)
        #expect(try #require(balanced.formValues).paidFor.map(\.shares) == [1000, 1000, 1000])

        let over = draft(
            amount: "30.00",
            splitMode: .byAmount,
            values: ["ana": "10.00", "bruno": "10.00", "chloe": "15.00"]
        )
        #expect(over.problems.contains(.amountsDoNotSumToTotal(difference: -500)))
    }

    @Test("Only included participants have to add up")
    func ignoresExcludedParticipants() {
        let form = draft(
            amount: "20.00",
            splitMode: .byAmount,
            values: ["ana": "10.00", "bruno": "10.00", "chloe": "999.00"],
            included: ["ana", "bruno"]
        )

        #expect(form.isValid)
    }

    @Test("A share of zero or less is rejected")
    func rejectsNonPositiveShares() {
        let form = draft(splitMode: .byShares, values: ["ana": "0", "bruno": "1", "chloe": "1"])

        #expect(form.problems.contains(.shareNotPositive("ana")))
        #expect(form.problems(forParticipant: "bruno").isEmpty)
    }

    @Test("An unparseable share is reported once, without a confusing sum error")
    func reportsUnparseableShare() {
        let form = draft(splitMode: .byAmount, values: ["ana": "abc", "bruno": "1", "chloe": "1"])

        #expect(form.problems.contains(.shareNotANumber("ana")))
        #expect(!form.problems.contains { if case .amountsDoNotSumToTotal = $0 { true } else { false } })
    }

    @Test("An invalid draft produces no payload")
    func withholdsPayloadWhenInvalid() {
        var form = draft()
        form.title = ""

        #expect(form.formValues == nil)
    }

    @Test("Editing an expense round-trips the split back into the fields")
    func loadsExistingExpense() throws {
        let expense = ExpenseDetails(
            id: "e1",
            groupId: "g1",
            title: "Apartment",
            amount: 48000,
            categoryId: 0,
            category: nil,
            expenseDate: .now,
            createdAt: .now,
            paidById: "chloe",
            paidBy: .init(id: "chloe", name: "Chloé"),
            paidFor: [
                .init(participantId: "ana", shares: 100),
                .init(participantId: "bruno", shares: 100),
                .init(participantId: "chloe", shares: 200),
            ],
            isReimbursement: false,
            splitMode: .byShares,
            notes: "Chloé took the double room.",
            documents: [],
            recurrenceRule: .never,
            originalAmount: nil,
            originalCurrency: nil,
            conversionRate: nil
        )

        let form = ExpenseFormDraft(
            editing: expense, group: group, locale: Locale(identifier: "en_US")
        )

        #expect(form.title == "Apartment")
        #expect(form.amountText == "480.00")
        #expect(form.splitMode == .byShares)
        #expect(form.paidByID == "chloe")
        #expect(form.participants.map(\.valueText) == ["1", "1", "2"])
        #expect(form.includedParticipants.count == 3)
        #expect(form.notes == "Chloé took the double room.")
        #expect(form.isValid)
    }

    @Test("Editing a by-amount expense shows amounts, not share counts")
    func loadsByAmountExpense() {
        let expense = ExpenseDetails(
            id: "e1", groupId: "g1", title: "Tram tickets", amount: 1800, categoryId: 0,
            category: nil, expenseDate: .now, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [
                .init(participantId: "ana", shares: 1000),
                .init(participantId: "bruno", shares: 800),
            ],
            isReimbursement: false, splitMode: .byAmount, notes: nil, documents: [],
            recurrenceRule: .never, originalAmount: nil, originalCurrency: nil,
            conversionRate: nil
        )

        let form = ExpenseFormDraft(
            editing: expense, group: group, locale: Locale(identifier: "en_US")
        )

        #expect(form.participants[0].valueText == "10.00")
        #expect(form.participants[1].valueText == "8.00")
        #expect(form.participants[2].isIncluded == false)
        #expect(form.isValid)
    }

    @Test("Settling a balance prefills a reimbursement between the two people")
    func buildsReimbursement() throws {
        let form = ExpenseFormDraft(
            settling: Reimbursement(from: "bruno", to: "ana", amount: 7797),
            group: group,
            title: "Reimbursement",
            locale: Locale(identifier: "en_US")
        )

        #expect(form.isReimbursement)
        #expect(form.paidByID == "bruno")
        #expect(form.includedParticipants.map(\.id) == ["ana"])
        #expect(form.amountText == "77.97")

        let values = try #require(form.formValues)
        #expect(values.amount == 7797)
        #expect(values.isReimbursement)
        #expect(values.paidFor.count == 1)
    }

    @Test("A comma decimal separator works for amounts and shares")
    func acceptsCommaSeparators() throws {
        var form = draft(amount: "30,00", splitMode: .byAmount,
                         values: ["ana": "10,00", "bruno": "10,00", "chloe": "10,00"])
        form.locale = Locale(identifier: "fr_FR")

        #expect(form.isValid)
        #expect(try #require(form.formValues).amount == 3000)
    }

    // MARK: - Currencies with no minor unit

    private var yenGroup: Group {
        Group(
            id: "g2", name: "Tokyo", information: nil, currency: "¥", currencyCode: "JPY",
            createdAt: .now,
            participants: [.init(id: "ana", name: "Ana"), .init(id: "bruno", name: "Bruno")]
        )
    }

    /// A group in yen stores whole yen, so "3000" typed there is ¥3,000 — not thirty of them.
    /// The by-amount shares are amounts too, and scale the same way; share counts do not.
    @Test("A group with no minor unit sends what was typed, unscaled")
    func sendsWholeUnitsForZeroDecimalCurrencies() throws {
        var form = ExpenseFormDraft(creatingIn: yenGroup, locale: Locale(identifier: "en_US"))
        form.title = "Sushi"
        form.amountText = "3000"
        form.splitMode = .byAmount
        form.participants[0].valueText = "1800"
        form.participants[1].valueText = "1200"

        #expect(form.minorUnitDigits == 0)
        #expect(form.isValid)

        let values = try #require(form.formValues)
        #expect(values.amount == 3000)
        #expect(values.paidFor.map(\.shares) == [1800, 1200])
    }

    @Test("Share counts stay scaled by 100 whatever the group counts in")
    func keepsShareScalingIndependentOfTheCurrency() throws {
        var form = ExpenseFormDraft(creatingIn: yenGroup, locale: Locale(identifier: "en_US"))
        form.title = "Sushi"
        form.amountText = "3000"
        form.splitMode = .byShares
        form.participants[0].valueText = "2"
        form.participants[1].valueText = "1"

        #expect(try #require(form.formValues).paidFor.map(\.shares) == [200, 100])
    }

    @Test("A yen expense loads back into the field as it was stored")
    func loadsZeroDecimalExpense() {
        let expense = ExpenseDetails(
            id: "e2", groupId: "g2", title: "Sushi", amount: 3000, categoryId: 0,
            category: nil, expenseDate: .now, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [
                .init(participantId: "ana", shares: 1800),
                .init(participantId: "bruno", shares: 1200),
            ],
            isReimbursement: false, splitMode: .byAmount, notes: nil, documents: [],
            recurrenceRule: .never, originalAmount: nil, originalCurrency: nil,
            conversionRate: nil
        )

        let form = ExpenseFormDraft(
            editing: expense, group: yenGroup, locale: Locale(identifier: "en_US")
        )

        #expect(form.amountText == "3000")
        #expect(form.participants.map(\.valueText) == ["1800", "1200"])
    }
}
