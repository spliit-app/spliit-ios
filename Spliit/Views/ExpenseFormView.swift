import SpliitAPI
import SpliitCore
import SwiftUI

/// Creating and editing an expense — who paid, how much, and how it's divided.
struct ExpenseFormView: View {

    enum Mode: Equatable {
        case create
        case edit(String)

        var isEditing: Bool { if case .edit = self { true } else { false } }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Wide enough for "100.00" at the body size, and it has to grow with the text or the
    /// digits are clipped long before the largest sizes.
    @ScaledMetric private var shareFieldWidth: CGFloat = 100

    let mode: Mode
    let group: SpliitAPI.Group
    let categories: [ExpenseCategory]
    /// Prefilled for a new expense; nil when editing, since it is fetched.
    let draft: ExpenseFormDraft?
    let onFinished: () async -> Void

    @State private var form: ExpenseFormDraft?
    @State private var hasAttemptedSave = false
    @State private var isSaving = false
    @State private var failure: String?

    /// Counters rather than flags: the same outcome twice in a row is still two outcomes, and a
    /// flag that is already true does not trigger anything.
    @State private var savedCount = 0
    @State private var refusedCount = 0

    @State private var rateLookup = RateLookup.idle
    /// The last rate this screen filled in by itself, so a rate the user typed over it is left
    /// alone by the next lookup.
    @State private var autoFilledRate: String?

    /// Stubbed from a launch argument under UI test, so a run neither depends on reaching an
    /// external service nor gets a different answer every day.
    private var rates: ExchangeRates {
        #if DEBUG
        if let stubbed = UITestSupport.stubbedExchangeRates() { return stubbed }
        #endif
        return ExchangeRates()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let form {
                    formBody(Binding(get: { form }, set: { self.form = $0 }))
                } else if failure != nil {
                    EmptyState(
                        art: .icon("exclamationmark.triangle"),
                        title: Text("Couldn’t load the expense"),
                        description: Text(failure ?? "")
                    )
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle(mode.isEditing ? "Edit expense" : "New expense")
            .trackScreen(mode.isEditing ? .groupEditExpense : .groupCreateExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.ExpenseForm.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isSaving || form == nil)
                        .accessibilityIdentifier(AccessibilityID.ExpenseForm.saveButton)
                }
            }
            .alert("Couldn’t save the expense", isPresented: .constant(failure != nil && form != nil)) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
        .task { await load() }
        .task(id: rateRequest) { await lookUpRate() }
        .interactiveDismissDisabled(isSaving)
        .sensoryFeedback(Haptics.saved, trigger: savedCount)
        .sensoryFeedback(Haptics.refused, trigger: refusedCount)
    }

    // MARK: - Form

    @ViewBuilder
    private func formBody(_ form: Binding<ExpenseFormDraft>) -> some View {
        Form {
            Section {
                TextField("What was it for?", text: form.title)
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.titleField)
                problem(for: [.titleTooShort])

                LabeledContent("Amount") {
                    if form.wrappedValue.conversionRequired {
                        convertedTotal(form.wrappedValue)
                    } else {
                        TextField(
                            "0\(decimalSeparator)00",
                            text: form.amountText
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .moneyInput()
                        .accessibilityIdentifier(AccessibilityID.ExpenseForm.amountField)
                    }
                }
                problem(for: [.amountMissing, .amountNotANumber, .amountZero, .amountTooLarge])

                DatePicker(
                    "Date",
                    selection: form.expenseDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.dateField)
            }

            currencySection(form)

            Section {
                Picker("Paid by", selection: form.paidByID) {
                    ForEach(group.participants) { participant in
                        Text(participant.name).tag(Optional(participant.id))
                    }
                }
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.paidByPicker)
                problem(for: [.payerMissing])

                if !categories.isEmpty {
                    Picker("Category", selection: form.categoryID) {
                        ForEach(groupedCategories, id: \.name) { grouping in
                            Section(grouping.name) {
                                ForEach(grouping.categories) { category in
                                    Text(category.displayName).tag(category.id)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.categoryPicker)
                }

                Toggle("This is a reimbursement", isOn: form.isReimbursement)
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.reimbursementToggle)
            }

            splitSection(form)

            Section("Notes") {
                TextField("Anything worth remembering?", text: form.notes, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.notesField)
            }

            if case .edit(let expenseID) = mode {
                Section {
                    Button("Delete expense", systemImage: "trash", role: .destructive) {
                        delete(expenseID)
                    }
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.deleteButton)
                }
            }
        }
    }

    // MARK: - Currency

    /// What the expense was paid in, and — when that is not what the group counts in — what was
    /// paid and at what rate.
    ///
    /// Absent entirely for a group that has only a free-text symbol: a conversion needs an ISO
    /// code on both sides, and a row that could never do anything is worse than no row. The
    /// currency picker in the group form is where that trade-off is explained.
    @ViewBuilder
    private func currencySection(_ form: Binding<ExpenseFormDraft>) -> some View {
        if let groupCode = group.currencyCode, groupCode.count == 3 {
            Section {
                NavigationLink {
                    CurrencyPickerView(
                        selectedCode: form.wrappedValue.originalCurrencyCode,
                        promotedCode: groupCode,
                        allowsCustomSymbol: false
                    ) { currency in
                        form.wrappedValue.useCurrency(currency?.code ?? groupCode)
                    }
                } label: {
                    LabeledContent("Paid in", value: currencyName(form.wrappedValue))
                }
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.currencyButton)

                if form.wrappedValue.conversionRequired {
                    LabeledContent("Amount paid") {
                        HStack(spacing: 4) {
                            TextField(
                                "0\(decimalSeparator)00",
                                text: form.originalAmountText
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .moneyInput()
                            .accessibilityIdentifier(
                                AccessibilityID.ExpenseForm.originalAmountField
                            )

                            Text(originalCurrency(form.wrappedValue)?.symbol ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    problem(for: [
                        .originalAmountMissing, .originalAmountNotANumber,
                        .originalAmountZero, .originalAmountTooLarge,
                    ])

                    LabeledContent("Exchange rate") {
                        TextField("0", text: form.conversionRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .moneyInput()
                            .accessibilityIdentifier(
                                AccessibilityID.ExpenseForm.conversionRateField
                            )
                    }
                    problem(for: [
                        .conversionRateMissing, .conversionRateNotANumber,
                        .conversionRateNotPositive,
                    ])
                }
            } header: {
                // Nothing to head, and nothing to explain, until the expense is in a currency
                // of its own: one row saying "Paid in — US Dollar" says what it is, and a
                // heading and a footnote over it on every expense in every group is furniture.
                if form.wrappedValue.conversionRequired {
                    Text("Currency")
                }
            } footer: {
                if form.wrappedValue.conversionRequired {
                    conversionFooter(form.wrappedValue)
                }
            }
        }
    }

    @ViewBuilder
    private func conversionFooter(_ form: ExpenseFormDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rateStatus(form))
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.conversionRateStatus)

            if canRefreshRate(form) {
                Button("Use the published rate") { Task { await refreshRate() } }
                    .font(.footnote)
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.refreshRateButton)
            }
        }
    }

    /// The total the conversion comes to, which is the amount the expense is stored at.
    ///
    /// Not editable while a conversion is in force: it is what the amount paid comes to at the
    /// rate given, and a total that could disagree with those two would be a total the rate
    /// beside it does not explain.
    @ViewBuilder
    private func convertedTotal(_ form: ExpenseFormDraft) -> some View {
        if let total = form.amountMinorUnits {
            Money(value: groupFormatter.string(minorUnits: total))
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.amountField)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Not yet known"))
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.amountField)
        }
    }

    /// Only where pressing it would change something: a rate typed by hand can be given up for
    /// the published one, and a lookup that failed can be tried again — but a field already
    /// holding what was just fetched has nothing to refresh, and a button that does nothing is
    /// worse than no button.
    private func canRefreshRate(_ form: ExpenseFormDraft) -> Bool {
        switch rateLookup {
        case .idle, .loading: false
        case .found: form.conversionRateText != autoFilledRate
        case .noRate, .unavailable: true
        }
    }

    /// What the footer says about where the rate in the field came from.
    private func rateStatus(_ form: ExpenseFormDraft) -> String {
        let base = form.originalCurrencyCode ?? ""
        let target = form.groupCurrencyCode ?? ""

        if form.conversionRateText != autoFilledRate, !form.conversionRateText.isEmpty {
            return String(localized: "Using the rate you entered.")
        }

        switch rateLookup {
        case .idle, .loading:
            return String(localized: "Getting the exchange rate…")
        case .found(let rate):
            let quote = String(
                localized: "\(base) 1 = \(target) \(ExpenseFormDraft.text(forRate: rate.rate))"
            )
            guard let day = rate.date, !Calendar.autoupdatingCurrent.isDate(
                day, inSameDayAs: form.expenseDate
            ) else {
                return quote
            }
            // Rates are published on working days, so a Sunday or a date still to come answers
            // with the last day there is one. Saying which day avoids the reasonable suspicion
            // that the number is simply wrong.
            let dayText = day.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "\(quote) — the rate on \(dayText).")
        case .noRate:
            return String(localized: "No published rate for this pair. Enter the rate yourself.")
        case .unavailable:
            return String(localized: "Couldn’t reach the rates service. Enter the rate yourself.")
        }
    }

    private func currencyName(_ form: ExpenseFormDraft) -> String {
        guard let currency = originalCurrency(form) else {
            return form.originalCurrencyCode ?? group.currency
        }
        return currency.name
    }

    private func originalCurrency(_ form: ExpenseFormDraft) -> Currency? {
        form.originalCurrencyCode.flatMap { Currency.named($0) }
    }

    private var groupFormatter: MoneyFormatter {
        MoneyFormatter(currencySymbol: group.currency, currencyCode: group.currencyCode)
    }

    @ViewBuilder
    private func splitSection(_ form: Binding<ExpenseFormDraft>) -> some View {
        Section {
            // Four segments share the width of the screen, so at accessibility sizes each label
            // is down to a character or two. A menu keeps the full words at any size.
            if dynamicTypeSize.isAccessibilitySize {
                splitModePicker(form).pickerStyle(.menu)
            } else {
                splitModePicker(form).pickerStyle(.segmented)
            }

            ForEach(form.participants) { $participant in
                AdaptiveHStack {
                    Toggle(isOn: $participant.isIncluded) {
                        Text(participant.name)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier(
                        AccessibilityID.ExpenseForm.participantToggle(participant.id)
                    )

                    if participant.isIncluded, form.wrappedValue.splitMode != .evenly {
                        HStack(spacing: 4) {
                            TextField("0", text: $participant.valueText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .moneyInput()
                                .frame(maxWidth: shareFieldWidth)
                                .accessibilityIdentifier(
                                    AccessibilityID.ExpenseForm.participantValue(participant.id)
                                )
                                // Only its position beside a name says whose share this is, and
                                // position is exactly what a screen reader flattens away.
                                .accessibilityLabel(Text("\(participant.name)’s share"))

                            Text(form.wrappedValue.splitMode.unitLabel(currency: group.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Paid for")
                Spacer()
                selectAllButton(form)
            }
        } footer: {
            splitFooter(form.wrappedValue)
        }
    }

    /// One control rather than two: with everyone already in the split, "select all" has nothing
    /// left to do, which is how the web app words it too.
    private func selectAllButton(_ form: Binding<ExpenseFormDraft>) -> some View {
        let allIncluded = form.wrappedValue.allParticipantsIncluded
        return Button(allIncluded ? "Select none" : "Select all") {
            form.wrappedValue.setAllParticipantsIncluded(!allIncluded)
        }
        // A control sitting in a section header inherits the muted header font, which reads as
        // one more caption rather than as something to tap. Plain, so it stays flat text beside
        // the heading instead of growing a button's own background.
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.accentColor)
        .accessibilityIdentifier(AccessibilityID.ExpenseForm.selectAllButton)
    }

    private func splitModePicker(_ form: Binding<ExpenseFormDraft>) -> some View {
        Picker("Split", selection: form.splitMode) {
            ForEach(SplitMode.allCases, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
                    .accessibilityIdentifier(
                        AccessibilityID.ExpenseForm.splitModeOption(mode.rawValue)
                    )
            }
        }
    }

    @ViewBuilder
    private func splitFooter(_ form: ExpenseFormDraft) -> some View {
        if hasAttemptedSave,
           let problem = form.problems.first(where: {
               if case .amountsDoNotSumToTotal = $0 { return true }
               if case .percentagesDoNotSumTo100 = $0 { return true }
               if case .noParticipantsSelected = $0 { return true }
               if case .shareNotPositive = $0 { return true }
               if case .shareNotANumber = $0 { return true }
               return false
           }) {
            Text(problem.message)
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.error)
        } else if let remainder = form.unallocated, remainder != 0 {
            // Showing what's left to allocate turns a rejected save into a running total.
            Text(remainderDescription(remainder, form: form))
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.remainder)
        } else {
            Text(form.splitMode.explanation)
        }
    }

    private func remainderDescription(_ remainder: Int, form: ExpenseFormDraft) -> String {
        switch form.splitMode {
        case .byAmount:
            let formatter = MoneyFormatter(
                currencySymbol: group.currency, currencyCode: group.currencyCode
            )
            return remainder > 0
                ? String(localized: "\(formatter.string(minorUnits: remainder)) still to allocate.")
                : String(localized: "\(formatter.string(minorUnits: -remainder)) over the total.")
        case .byPercentage:
            let percent = Decimal(abs(remainder)) / 100
            return remainder > 0
                ? String(localized: "\(percent.formatted())% still to allocate.")
                : String(localized: "\(percent.formatted())% over 100%.")
        case .evenly, .byShares:
            return ""
        }
    }

    @ViewBuilder
    private func problem(for candidates: [ExpenseFormDraft.Problem]) -> some View {
        if hasAttemptedSave, let form,
           let problem = form.problems.first(where: candidates.contains) {
            Text(problem.message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.error)
        }
    }

    /// Sorted on the translated names, not the English the server sent, and with the locale's own
    /// collation — otherwise a French picker runs in English alphabetical order and "Épicerie"
    /// sorts after "Vêtements" on the strength of its accent.
    private var groupedCategories: [(name: String, categories: [ExpenseCategory])] {
        Dictionary(grouping: categories, by: \.grouping)
            .map { grouping, categories in
                (
                    name: ExpenseCategory.displayHeading(grouping),
                    categories: categories.sorted {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var decimalSeparator: String {
        Locale.autoupdatingCurrent.decimalSeparator ?? "."
    }

    // MARK: - Actions

    private enum RateLookup: Equatable {
        case idle
        case loading
        case found(ExchangeRate)
        case noRate
        case unavailable
    }

    /// What to ask the rates service for, and nil when there is nothing to ask. Doubles as the
    /// identity of the lookup task, so changing the date or either currency starts a new one and
    /// abandons the answer to the old question.
    private struct RateRequest: Equatable {
        let day: String
        let base: String
        let target: String
    }

    private var rateRequest: RateRequest? {
        guard let form, form.conversionRequired,
              let base = form.originalCurrencyCode,
              let target = form.groupCurrencyCode
        else { return nil }
        return RateRequest(
            day: ExchangeRates.day(of: form.expenseDate), base: base, target: target
        )
    }

    private func lookUpRate() async {
        guard let request = rateRequest else {
            rateLookup = .idle
            return
        }
        rateLookup = .loading
        do {
            let rate = try await rates.rate(
                on: request.day, from: request.base, to: request.target
            )
            rateLookup = .found(rate)
            // Only into a field the user has not made their own. The rate a card was actually
            // charged at beats a published one, and typing it must not be undone by a lookup
            // that arrives afterwards.
            if form?.conversionRateText.isEmpty == true
                || form?.conversionRateText == autoFilledRate {
                apply(rate.rate)
            }
        } catch ExchangeRates.Failure.noRateForCurrency {
            rateLookup = .noRate
        } catch {
            rateLookup = .unavailable
        }
    }

    /// Asks again, and takes the answer whatever is in the field — this is the way back from a
    /// rate typed by hand, and the retry after a lookup that failed.
    private func refreshRate() async {
        guard let request = rateRequest else { return }
        rateLookup = .loading
        do {
            let rate = try await rates.rate(
                on: request.day, from: request.base, to: request.target
            )
            rateLookup = .found(rate)
            apply(rate.rate)
        } catch ExchangeRates.Failure.noRateForCurrency {
            rateLookup = .noRate
        } catch {
            rateLookup = .unavailable
        }
    }

    private func apply(_ rate: Decimal) {
        form?.use(rate: rate)
        autoFilledRate = form?.conversionRateText
    }

    private func load() async {
        if let draft {
            form = draft
            return
        }
        guard case .edit(let expenseID) = mode else { return }
        do {
            let response = try await app.client.call(
                Spliit.expense(groupId: group.id, expenseId: expenseID)
            )
            form = ExpenseFormDraft(editing: response.expense, group: group)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func save() {
        hasAttemptedSave = true
        guard let form, let values = form.formValues else {
            // Refused before anything was sent. The problems appear beside the fields that have
            // them, which may be off the bottom of a long form.
            refusedCount += 1
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                switch mode {
                case .create:
                    _ = try await app.client.call(
                        Spliit.createExpense(groupId: group.id, values, by: actorID)
                    )
                    Analytics.shared.event(.createExpense)
                case .edit(let expenseID):
                    _ = try await app.client.call(
                        Spliit.updateExpense(
                            groupId: group.id, expenseId: expenseID, values, by: actorID
                        )
                    )
                }
                // Before the reload, so it lands with the save rather than after the list has
                // caught up — and while this view is still on screen to play it.
                savedCount += 1
                await onFinished()
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Who the activity log should credit for this save: the participant the user has said they
    /// are in this group, or nil — which the log reads as "Someone", accurately.
    private var actorID: String? {
        app.recentGroups.actorID(inGroup: group.id, participants: group.participants)
    }

    private func delete(_ expenseID: String) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await app.client.call(
                    Spliit.deleteExpense(
                        groupId: group.id, expenseId: expenseID, by: actorID
                    )
                )
                await onFinished()
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Split mode presentation

extension SplitMode {
    var title: LocalizedStringKey {
        switch self {
        case .evenly: "Evenly"
        case .byShares: "Shares"
        case .byPercentage: "Percent"
        case .byAmount: "Amount"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .evenly: "Everyone selected pays an equal part."
        case .byShares: "Give anyone paying a larger part more shares."
        case .byPercentage: "Percentages must add up to 100."
        case .byAmount: "Amounts must add up to the expense total."
        }
    }

    func unitLabel(currency: String) -> String {
        switch self {
        case .evenly: ""
        case .byShares: String(localized: "shares")
        case .byPercentage: "%"
        case .byAmount: currency
        }
    }
}

/// A leading checkbox, closer to the old app's list than a trailing switch and much less
/// cramped once a value field shares the row.
private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                    .imageScale(.large)
                configuration.label
                    .foregroundStyle(.primary)
            }
            // Claim the rest of the row, so the tappable area matches the area the row appears
            // to occupy. Sized to its content, the checkbox left most of the row dead to a tap
            // and put the centre an assistive technology aims for outside the control.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Built out of a Button, so VoiceOver would otherwise call it one and never say whether
        // the participant is in the split — the filled checkmark is the only cue there is, and
        // it is purely visual. Representing it as the Toggle it actually is restores the state
        // and the "double tap to toggle" that comes with it.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
