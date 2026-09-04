import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Remembered split")
struct DefaultSplitTests {

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
        splitMode: SplitMode = .evenly,
        values: [String: String] = [:],
        included: [String] = ["ana", "bruno", "chloe"]
    ) -> ExpenseFormDraft {
        var form = ExpenseFormDraft(creatingIn: group, locale: Locale(identifier: "en_US"))
        form.title = "Airport taxi"
        form.amountText = "100.00"
        form.splitMode = splitMode
        form.participants = form.participants.map {
            var participant = $0
            participant.isIncluded = included.contains($0.id)
            if let value = values[$0.id] { participant.valueText = value }
            return participant
        }
        return form
    }

    // MARK: - What gets remembered

    @Test("A saved expense remembers its mode and everyone's share")
    func remembersModeAndShares() throws {
        let values = try #require(
            draft(
                splitMode: .byPercentage,
                values: ["ana": "70", "bruno": "20", "chloe": "10"]
            ).formValues
        )

        let split = DefaultSplit(remembering: values, participants: group.participants)

        #expect(split.splitMode == .byPercentage)
        #expect(split.shares == ["ana": 7000, "bruno": 2000, "chloe": 1000])
    }

    /// Who is in the split is half of what makes one worth keeping: the flatshare where two of
    /// three people share the car is remembered by those two names.
    @Test("Only the people in the split are remembered")
    func remembersOnlyTheIncluded() throws {
        let values = try #require(draft(included: ["ana", "bruno"]).formValues)

        let split = DefaultSplit(remembering: values, participants: group.participants)

        #expect(split.splitMode == .evenly)
        #expect(split.shares == ["ana": 100, "bruno": 100])
    }

    /// Its shares are one receipt's amounts, and they add up to that receipt's total. Carrying
    /// them to the next expense would produce a split that cannot be saved.
    @Test("A by-amount split remembers the mode and nothing else")
    func remembersOnlyTheModeForAmounts() throws {
        let values = try #require(
            draft(
                splitMode: .byAmount,
                values: ["ana": "50.00", "bruno": "30.00", "chloe": "20.00"]
            ).formValues
        )

        let split = DefaultSplit(remembering: values, participants: group.participants)

        #expect(split.splitMode == .byAmount)
        #expect(split.shares == nil)
    }

    /// Stored as three names it would be a split of Ana, Bruno and Chloé — and Dimitri, who
    /// moves in next month, would be left out of every expense without a word being said.
    @Test("An even split of the whole group remembers the group, not its names")
    func remembersTheWholeGroupAsMembership() throws {
        let values = try #require(draft().formValues)

        let split = DefaultSplit(remembering: values, participants: group.participants)

        #expect(split.splitMode == .evenly)
        #expect(split.shares == nil)
    }

    @Test("So somebody who joins afterwards is in the split too")
    func includesANewParticipant() throws {
        let values = try #require(draft().formValues)
        let split = DefaultSplit(remembering: values, participants: group.participants)

        let joined = Group(
            id: group.id,
            name: group.name,
            information: nil,
            currency: group.currency,
            currencyCode: group.currencyCode,
            createdAt: group.createdAt,
            participants: group.participants + [.init(id: "dimitri", name: "Dimitri")]
        )
        let form = ExpenseFormDraft(
            creatingIn: joined, defaultSplit: split, locale: Locale(identifier: "en_US")
        )

        #expect(form.includedParticipants.map(\.id) == ["ana", "bruno", "chloe", "dimitri"])
    }

    /// Not under the modes whose numbers mean something: nobody can be added to 50/30/20
    /// without breaking it, so the newcomer waits for an expense that says what they owe.
    @Test("A whole-group percentage split still remembers its names")
    func remembersNamesUnderPercentages() throws {
        let values = try #require(
            draft(
                splitMode: .byPercentage,
                values: ["ana": "50", "bruno": "30", "chloe": "20"]
            ).formValues
        )

        let split = DefaultSplit(remembering: values, participants: group.participants)

        #expect(split.shares == ["ana": 5000, "bruno": 3000, "chloe": 2000])
    }

    @Test("The flag the web app sends travels with the expense")
    func sendsTheFlag() throws {
        var form = draft()
        form.saveSplitAsDefault = true

        #expect(try #require(form.formValues).saveDefaultSplittingOptions)
        #expect(try #require(draft().formValues).saveDefaultSplittingOptions == false)
    }

    /// One person handing money to one other is not how the group's expenses are divided, and
    /// remembering it would leave every later expense paid for by whoever was owed.
    @Test("A reimbursement is not a split worth remembering")
    func doesNotOfferToRememberAReimbursement() {
        var form = draft()
        #expect(form.isSplitWorthRemembering)

        form.isReimbursement = true
        #expect(!form.isSplitWorthRemembering)
    }

    // MARK: - What a new expense starts from

    @Test("A new expense starts from the remembered split")
    func appliesTheRememberedSplit() {
        let form = ExpenseFormDraft(
            creatingIn: group,
            defaultSplit: DefaultSplit(
                splitMode: .byPercentage,
                shares: ["ana": 7000, "bruno": 2000, "chloe": 1000]
            ),
            locale: Locale(identifier: "en_US")
        )

        #expect(form.splitMode == .byPercentage)
        #expect(form.participants.map(\.valueText) == ["70", "20", "10"])
        #expect(form.includedParticipants.count == 3)
        // Nothing is remembered about what an expense was for, only how it was divided.
        #expect(form.title.isEmpty)
        #expect(form.amountText.isEmpty)
    }

    @Test("A remembered split covering some of the group leaves the rest out")
    func appliesAPartialSplit() {
        let form = ExpenseFormDraft(
            creatingIn: group,
            defaultSplit: DefaultSplit(splitMode: .evenly, shares: ["ana": 100, "bruno": 100]),
            locale: Locale(identifier: "en_US")
        )

        #expect(form.includedParticipants.map(\.id) == ["ana", "bruno"])
    }

    /// Fractions of a share survive the ×100 scale they are stored on, and land in the field
    /// spelled the way editing an expense spells them.
    @Test("A remembered half share comes back the way an edited one does")
    func appliesFractionalShares() {
        let form = ExpenseFormDraft(
            creatingIn: group,
            defaultSplit: DefaultSplit(
                splitMode: .byShares,
                shares: ["ana": 150, "bruno": 100, "chloe": 100]
            ),
            locale: Locale(identifier: "en_US")
        )

        #expect(form.participants.map(\.valueText) == ["1.50", "1", "1"])
    }

    @Test("A remembered by-amount split sets the mode and puts the group back in the split")
    func appliesAByAmountSplit() {
        let form = ExpenseFormDraft(
            creatingIn: group,
            defaultSplit: DefaultSplit(splitMode: .byAmount),
            locale: Locale(identifier: "en_US")
        )

        #expect(form.splitMode == .byAmount)
        #expect(form.includedParticipants.count == 3)
    }

    /// The alternative is worse than forgetting: dropping the name that left turns 70/30 into a
    /// 70 that no percentage split will accept, and does it without saying so.
    @Test("A split naming somebody who has left the group is dropped whole")
    func ignoresAStaleSplit() {
        let stale = DefaultSplit(
            splitMode: .byPercentage,
            shares: ["ana": 7000, "dimitri": 3000]
        )
        #expect(!stale.applies(to: group.participants))

        let form = ExpenseFormDraft(
            creatingIn: group, defaultSplit: stale, locale: Locale(identifier: "en_US")
        )

        #expect(form.splitMode == .evenly)
        #expect(form.includedParticipants.count == 3)
    }

    /// Somebody joining is not somebody leaving: the split still describes what it described,
    /// and the newcomer is simply not in it until an expense says otherwise.
    @Test("A new participant leaves a remembered split standing")
    func survivesANewParticipant() {
        let split = DefaultSplit(splitMode: .evenly, shares: ["ana": 100, "bruno": 100])

        #expect(split.applies(to: group.participants))
    }

    @Test("Remembering a by-amount split says nothing about who is in the group")
    func aByAmountSplitAlwaysApplies() {
        #expect(DefaultSplit(splitMode: .byAmount).applies(to: []))
    }
}
