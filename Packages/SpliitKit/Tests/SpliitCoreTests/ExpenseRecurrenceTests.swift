import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

/// What the form can promise about a recurring expense, which is not simply "the rule applied to
/// the date on screen": `groups.expenses.update` moves a schedule only when the rule changes,
/// counts from the date the expense already had, and will not touch one that has already been
/// acted on. Getting any of those wrong means showing a date the server has no intention of
/// honouring.
@Suite("Expense recurrence in the form")
struct ExpenseRecurrenceTests {

    private let group = Group(
        id: "g1",
        name: "Flat share",
        information: nil,
        currency: "€",
        currencyCode: "EUR",
        createdAt: .now,
        participants: [
            .init(id: "ana", name: "Ana"),
            .init(id: "bruno", name: "Bruno"),
        ]
    )

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func expense(
        rule: RecurrenceRule?,
        date: Date,
        link: RecurringExpenseLink?
    ) -> ExpenseDetails {
        ExpenseDetails(
            id: "e1", groupId: "g1", title: "Rent", amount: 90000, categoryId: 0,
            category: nil, expenseDate: date, createdAt: .now, paidById: "ana",
            paidBy: .init(id: "ana", name: "Ana"),
            paidFor: [
                .init(participantId: "ana", shares: 100),
                .init(participantId: "bruno", shares: 100),
            ],
            isReimbursement: false, splitMode: .evenly, notes: nil, documents: [],
            recurrenceRule: rule, recurringExpenseLink: link,
            originalAmount: nil, originalCurrency: nil, conversionRate: nil
        )
    }

    @Test("A new expense doesn't repeat, and says nothing about when it would")
    func newExpenseDoesNotRepeat() {
        let form = ExpenseFormDraft(creatingIn: group)

        #expect(form.recurrenceRule == .never)
        #expect(form.nextRecurrenceDate == nil)
        #expect(!form.hasAlreadyRepeated)
    }

    @Test("On a new expense the next one is counted from the date on the form")
    func countsFromTheFormDate() {
        var form = ExpenseFormDraft(creatingIn: group)
        form.expenseDate = utc(2026, 1, 31)
        form.recurrenceRule = .monthly

        #expect(form.nextRecurrenceDate == utc(2026, 2, 28))
    }

    @Test("The rule reaches the payload")
    func sendsTheRule() throws {
        var form = ExpenseFormDraft(creatingIn: group, locale: Locale(identifier: "en_US"))
        form.title = "Rent"
        form.amountText = "900.00"
        form.recurrenceRule = .monthly

        let values = try #require(form.formValues)
        #expect(values.recurrenceRule == .monthly)
    }

    @Test("Editing reads back the recurrence the expense was saved with")
    func loadsTheRule() {
        let form = ExpenseFormDraft(
            editing: expense(
                rule: .weekly,
                date: utc(2026, 9, 1),
                link: RecurringExpenseLink(id: "l1", nextExpenseDate: utc(2026, 9, 8))
            ),
            group: group,
            locale: Locale(identifier: "en_US")
        )

        #expect(form.recurrenceRule == .weekly)
        #expect(!form.hasAlreadyRepeated)
        #expect(form.nextRecurrenceDate == utc(2026, 9, 8))
    }

    /// The rule is unchanged, so `isUpdateRecurrenceExpenseLink` is false and the server leaves
    /// `nextExpenseDate` alone — moving the expense does not move what comes after it.
    @Test("Moving a recurring expense leaves the next one where the server put it")
    func keepsTheServersDateWhenOnlyTheDateMoves() {
        var form = ExpenseFormDraft(
            editing: expense(
                rule: .weekly,
                date: utc(2026, 9, 1),
                link: RecurringExpenseLink(id: "l1", nextExpenseDate: utc(2026, 9, 8))
            ),
            group: group,
            locale: Locale(identifier: "en_US")
        )
        form.expenseDate = utc(2026, 9, 4)

        #expect(form.nextRecurrenceDate == utc(2026, 9, 8))
    }

    /// The server recomputes from `existingExpense.expenseDate` — the date the expense already
    /// had, not the one being saved alongside the new rule.
    @Test("Changing the rule counts from the date the expense already had")
    func countsFromTheLoadedDateWhenTheRuleChanges() {
        var form = ExpenseFormDraft(
            editing: expense(
                rule: .weekly,
                date: utc(2026, 9, 1),
                link: RecurringExpenseLink(id: "l1", nextExpenseDate: utc(2026, 9, 8))
            ),
            group: group,
            locale: Locale(identifier: "en_US")
        )
        form.recurrenceRule = .monthly
        form.expenseDate = utc(2026, 9, 20)

        #expect(form.nextRecurrenceDate == utc(2026, 10, 1))
    }

    /// No link yet, so the server makes one and counts it from the date being saved.
    @Test("Adding a recurrence to an expense that had none counts from the form")
    func countsFromTheFormWhenThereIsNoLink() {
        var form = ExpenseFormDraft(
            editing: expense(rule: .never, date: utc(2026, 9, 1), link: nil),
            group: group,
            locale: Locale(identifier: "en_US")
        )
        form.recurrenceRule = .daily
        form.expenseDate = utc(2026, 9, 20)

        #expect(form.nextRecurrenceDate == utc(2026, 9, 21))
    }

    /// A stamped link is a series that has moved on: the server writes the `recurrenceRule`
    /// column and schedules nothing, whichever way the rule is changed. Both directions are
    /// worth pinning down, because the harmful one is switching to "Never" and believing the
    /// series has stopped.
    @Test("An expense that has already repeated schedules nothing further")
    func aStampedLinkSchedulesNothing() {
        let stamped = RecurringExpenseLink(
            id: "l1", nextExpenseDate: utc(2026, 10, 1), nextExpenseCreatedAt: utc(2026, 10, 1)
        )
        var form = ExpenseFormDraft(
            editing: expense(rule: .monthly, date: utc(2026, 9, 1), link: stamped),
            group: group,
            locale: Locale(identifier: "en_US")
        )

        #expect(form.hasAlreadyRepeated)
        #expect(form.nextRecurrenceDate == nil)

        form.recurrenceRule = .never
        #expect(form.hasAlreadyRepeated)
        #expect(form.nextRecurrenceDate == nil)

        form.recurrenceRule = .weekly
        #expect(form.nextRecurrenceDate == nil)
    }
}
