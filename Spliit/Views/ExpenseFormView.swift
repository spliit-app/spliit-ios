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
            .trackScreen(
                mode.isEditing ? .groupEditExpense : .groupCreateExpense,
                properties: ["groupId": group.id]
            )
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
        .interactiveDismissDisabled(isSaving)
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
                    TextField(
                        "0\(decimalSeparator)00",
                        text: form.amountText
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(AccessibilityID.ExpenseForm.amountField)
                }
                problem(for: [.amountMissing, .amountNotANumber, .amountZero, .amountTooLarge])

                DatePicker(
                    "Date",
                    selection: form.expenseDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier(AccessibilityID.ExpenseForm.dateField)
            }

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
                                    Text(category.name).tag(category.id)
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
            Text("Paid for")
        } footer: {
            splitFooter(form.wrappedValue)
        }
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

    private var groupedCategories: [(name: String, categories: [ExpenseCategory])] {
        Dictionary(grouping: categories, by: \.grouping)
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, categories: $0.value.sorted { $0.name < $1.name }) }
    }

    private var decimalSeparator: String {
        Locale.autoupdatingCurrent.decimalSeparator ?? "."
    }

    // MARK: - Actions

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
        guard let form, let values = form.formValues else { return }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                switch mode {
                case .create:
                    _ = try await app.client.call(
                        Spliit.createExpense(groupId: group.id, values)
                    )
                    Analytics.shared.event(.createExpense, properties: ["groupId": group.id])
                case .edit(let expenseID):
                    _ = try await app.client.call(
                        Spliit.updateExpense(groupId: group.id, expenseId: expenseID, values)
                    )
                }
                await onFinished()
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func delete(_ expenseID: String) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await app.client.call(
                    Spliit.deleteExpense(groupId: group.id, expenseId: expenseID)
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
