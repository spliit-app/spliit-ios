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

    @Test("A new expense is paid by whoever you said you are")
    func defaultsToTheActiveParticipant() {
        let form = ExpenseFormDraft(creatingIn: group, paidBy: "bruno")

        #expect(form.paidByID == "bruno")
    }

    /// Nobody has answered the question yet, so the form falls back to what it always did.
    @Test("Without an answer, the first participant pays")
    func defaultsToTheFirstParticipant() {
        #expect(ExpenseFormDraft(creatingIn: group).paidByID == "ana")
    }

    /// The stored answer outlives the participant it names: a group can drop somebody between
    /// one launch and the next, and the payer picker must not open on a person who is gone.
    @Test("A payer the group no longer has falls back to the first participant")
    func ignoresAStalePayer() {
        #expect(ExpenseFormDraft(creatingIn: group, paidBy: "chloe-who-left").paidByID == "ana")
    }

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

    @Test("A blank expense already covers the whole group")
    func reportsEveryoneIncluded() {
        #expect(draft().allParticipantsIncluded)
        #expect(!draft(included: ["ana", "bruno"]).allParticipantsIncluded)
        #expect(!draft(included: []).allParticipantsIncluded)
    }

    @Test("Selecting all puts everyone in the split, selecting none empties it")
    func selectsAllOrNone() {
        var form = draft(included: ["ana"])

        form.setAllParticipantsIncluded(true)
        #expect(form.includedParticipants.map(\.id) == ["ana", "bruno", "chloe"])
        #expect(form.allParticipantsIncluded)

        form.setAllParticipantsIncluded(false)
        #expect(form.includedParticipants.isEmpty)
        #expect(!form.allParticipantsIncluded)
        #expect(form.problems.contains(.noParticipantsSelected))
    }

    /// The rows never leave the draft, so the numbers survive the round trip — unlike the web
    /// app, which rebuilds the list and gives anyone re-added a share of 1.
    @Test("Deselecting everyone and back again keeps the shares that were typed")
    func keepsSharesAcrossSelectAll() throws {
        var form = draft(
            amount: "30.00",
            splitMode: .byAmount,
            values: ["ana": "5.00", "bruno": "10.00", "chloe": "15.00"]
        )

        form.setAllParticipantsIncluded(false)
        form.setAllParticipantsIncluded(true)

        let values = try #require(form.formValues)
        #expect(values.paidFor.map(\.shares) == [500, 1000, 1500])
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

// MARK: - Expenses paid in another currency

@Suite("Expense currency conversion")
struct ExpenseConversionTests {

    private let euroGroup = Group(
        id: "g1", name: "Weekend in Lisbon", information: nil, currency: "€",
        currencyCode: "EUR", createdAt: .now,
        participants: [.init(id: "ana", name: "Ana"), .init(id: "bruno", name: "Bruno")]
    )

    private let yenGroup = Group(
        id: "g2", name: "Tokyo", information: nil, currency: "¥", currencyCode: "JPY",
        createdAt: .now,
        participants: [.init(id: "ana", name: "Ana"), .init(id: "bruno", name: "Bruno")]
    )

    /// A group that only ever had a symbol, which is every group created before the web app
    /// grew a currency picker.
    private let symbolOnlyGroup = Group(
        id: "g3", name: "Flat", information: nil, currency: "kr", currencyCode: nil,
        createdAt: .now,
        participants: [.init(id: "ana", name: "Ana"), .init(id: "bruno", name: "Bruno")]
    )

    private func draft(
        in group: Group,
        paidIn code: String? = nil,
        paid: String = "",
        rate: String = "",
        locale: Locale = Locale(identifier: "en_US")
    ) -> ExpenseFormDraft {
        var form = ExpenseFormDraft(creatingIn: group, locale: locale)
        form.title = "Airport taxi"
        if let code { form.originalCurrencyCode = code }
        form.originalAmountText = paid
        form.conversionRateText = rate
        return form
    }

    @Test("An expense in the group's own currency records no conversion")
    func recordsNoConversionByDefault() throws {
        var form = draft(in: euroGroup)
        form.amountText = "42.50"

        #expect(form.conversionRequired == false)
        let values = try #require(form.formValues)
        #expect(values.amount == 4250)
        #expect(values.originalAmount == nil)
        #expect(values.originalCurrency == nil)
        #expect(values.conversionRate == nil)
    }

    @Test("An expense paid in another currency is stored at what it converts to")
    func convertsToTheGroupCurrency() throws {
        let form = draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "0.92")

        #expect(form.conversionRequired)
        #expect(form.amountMinorUnits == 3680)

        let values = try #require(form.formValues)
        #expect(values.amount == 3680)
        #expect(values.originalAmount == 4000)
        #expect(values.originalCurrency == "USD")
        #expect(values.conversionRate == Decimal(string: "0.92"))
    }

    /// The two sides of a conversion count in their own minor units. €40.00 is 4000 and the
    /// ¥6,540 it comes to is 6540 — not 654,000, and not 65.
    @Test("Each side of the conversion uses its own minor units")
    func scalesEachSideByItsOwnCurrency() throws {
        let intoYen = draft(in: yenGroup, paidIn: "EUR", paid: "40.00", rate: "163.5")

        #expect(intoYen.originalMinorUnitDigits == 2)
        #expect(intoYen.minorUnitDigits == 0)
        #expect(intoYen.originalAmountMinorUnits == 4000)
        #expect(intoYen.amountMinorUnits == 6540)

        let outOfYen = draft(in: euroGroup, paidIn: "JPY", paid: "3000", rate: "0.0058")

        #expect(outOfYen.originalAmountMinorUnits == 3000)
        #expect(outOfYen.amountMinorUnits == 1740)
    }

    /// Three of the Gulf currencies keep three digits, so the amount paid has to as well.
    @Test("A three-digit currency keeps its third digit")
    func handlesThreeDigitCurrencies() throws {
        let form = draft(in: euroGroup, paidIn: "BHD", paid: "12.345", rate: "2.44")

        #expect(form.originalMinorUnitDigits == 3)
        #expect(form.originalAmountMinorUnits == 12345)
        // 12.345 × 2.44 = 30.1218, to the euro's two digits.
        #expect(form.amountMinorUnits == 3012)
    }

    @Test("The amount paid must be there, numeric, non-zero and under ten million")
    func validatesTheAmountPaid() {
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "", rate: "0.92")
                .problems.contains(.originalAmountMissing)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "lots", rate: "0.92")
                .problems.contains(.originalAmountNotANumber)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "0", rate: "0.92")
                .problems.contains(.originalAmountZero)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "10000000.01", rate: "0.92")
                .problems.contains(.originalAmountTooLarge)
        )
    }

    @Test("The rate must be there and strictly positive")
    func validatesTheRate() {
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "")
                .problems.contains(.conversionRateMissing)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "par")
                .problems.contains(.conversionRateNotANumber)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "0")
                .problems.contains(.conversionRateNotPositive)
        )
        #expect(
            draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "-1")
                .problems.contains(.conversionRateNotPositive)
        )
    }

    /// The amount paid and the rate can each be fine on their own and still come to nothing —
    /// which would be an expense the balances silently ignore.
    @Test("A rate that rounds the total away is refused")
    func refusesATotalThatRoundsToZero() {
        let form = draft(in: euroGroup, paidIn: "USD", paid: "0.01", rate: "0.0001")

        #expect(form.amountMinorUnits == 0)
        #expect(form.problems.contains(.amountZero))
    }

    @Test("A group with only a symbol cannot convert anything")
    func refusesToConvertWithoutAnISOCode() throws {
        var form = draft(in: symbolOnlyGroup, paidIn: "USD", paid: "40.00", rate: "0.92")
        form.amountText = "42.50"

        #expect(form.conversionRequired == false)
        // The typed total still stands, and nothing about a conversion is sent.
        let values = try #require(form.formValues)
        #expect(values.amount == 4250)
        #expect(values.originalCurrency == nil)
    }

    @Test("Editing an expense loads its conversion back into the fields")
    func loadsAnExistingConversion() {
        let expense = ExpenseDetails(
            id: "e1", groupId: "g1", title: "Airport taxi", amount: 3680, categoryId: 0,
            category: nil, expenseDate: .now, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [.init(participantId: "ana", shares: 100)],
            isReimbursement: false, splitMode: .evenly, notes: nil, documents: [],
            recurrenceRule: .never,
            originalAmount: 4000, originalCurrency: "USD",
            conversionRate: LenientDecimal(Decimal(string: "0.92")!)
        )

        let form = ExpenseFormDraft(
            editing: expense, group: euroGroup, locale: Locale(identifier: "en_US")
        )

        #expect(form.conversionRequired)
        #expect(form.originalCurrencyCode == "USD")
        #expect(form.originalAmountText == "40.00")
        #expect(form.conversionRateText == "0.92")
        #expect(form.amountMinorUnits == expense.amount)
    }

    /// An expense saved before any of this existed has no currency of its own, and belongs to
    /// whatever the group counts in.
    @Test("An expense with no currency of its own is in the group's")
    func loadsAnExpenseWithoutAConversion() {
        let expense = ExpenseDetails(
            id: "e2", groupId: "g1", title: "Coffee", amount: 450, categoryId: 0,
            category: nil, expenseDate: .now, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [.init(participantId: "ana", shares: 100)],
            isReimbursement: false, splitMode: .evenly, notes: nil, documents: [],
            recurrenceRule: .never,
            originalAmount: nil, originalCurrency: nil, conversionRate: nil
        )

        let form = ExpenseFormDraft(
            editing: expense, group: euroGroup, locale: Locale(identifier: "en_US")
        )

        #expect(form.originalCurrencyCode == "EUR")
        #expect(form.conversionRequired == false)
        #expect(form.amountText == "4.50")
    }

    /// The server cannot clear the amount and the rate — only the currency — so an expense that
    /// used to be converted keeps both, with nothing reading them. Loading one has to ignore
    /// them, or a currency picked afterwards would arrive with someone else's numbers in it.
    @Test("What a cleared conversion left behind is not read back")
    func ignoresALeftoverConversion() {
        let expense = ExpenseDetails(
            id: "e3", groupId: "g1", title: "Dinner", amount: 3696, categoryId: 0,
            category: nil, expenseDate: .now, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [.init(participantId: "ana", shares: 100)],
            isReimbursement: false, splitMode: .evenly, notes: nil, documents: [],
            recurrenceRule: .never,
            originalAmount: 4000, originalCurrency: nil,
            conversionRate: LenientDecimal(Decimal(string: "0.9241")!)
        )

        let form = ExpenseFormDraft(
            editing: expense, group: euroGroup, locale: Locale(identifier: "en_US")
        )

        #expect(form.conversionRequired == false)
        #expect(form.originalAmountText.isEmpty)
        #expect(form.conversionRateText.isEmpty)
        #expect(form.amountText == "36.96")
    }

    /// Moving back has to clear the currency, and a nil optional would not: it is left out of the
    /// request and Prisma leaves the column alone. See `ExpenseFormValues.encode(to:)`.
    @Test("Moving an expense back to the group's currency keeps the total and drops the rate")
    func clearsTheConversionOnTheWayBack() throws {
        var form = draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "0.92")
        form.useCurrency("EUR")

        #expect(form.conversionRequired == false)
        #expect(form.amountText == "36.80")

        let values = try #require(form.formValues)
        #expect(values.amount == 3680)
        #expect(values.originalAmount == nil)
        #expect(values.originalCurrency == nil)
        #expect(values.conversionRate == nil)
    }

    /// A rate is a rate between two currencies. Carrying one to a different pair would convert
    /// at a number that is right for a conversion nobody asked for.
    @Test("Changing the currency drops the rate but keeps what was paid")
    func dropsTheRateWithTheCurrency() {
        var form = draft(in: euroGroup, paidIn: "USD", paid: "40.00", rate: "0.92")
        form.useCurrency("GBP")

        #expect(form.originalAmountText == "40.00")
        #expect(form.conversionRateText.isEmpty)
        #expect(form.problems.contains(.conversionRateMissing))
    }

    @Test("A comma decimal separator works for the amount paid and the rate")
    func parsesACommaSeparator() throws {
        let form = draft(
            in: euroGroup, paidIn: "USD", paid: "40,00", rate: "0,92",
            locale: Locale(identifier: "fr_FR")
        )

        #expect(form.isValid)
        #expect(try #require(form.formValues).amount == 3680)
    }

    @Test("A looked-up rate lands in the field at the precision it arrived with")
    func takesALookedUpRate() {
        var form = draft(in: euroGroup, paidIn: "USD", paid: "40.00")
        form.use(rate: Decimal(string: "0.9241")!)

        #expect(form.conversionRateText == "0.9241")
        #expect(form.amountMinorUnits == 3696)
    }
}
