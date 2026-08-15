import SpliitAPI
import SpliitCore
import SwiftUI

/// The group editor, shared by "Create group" and "Group settings".
///
/// Errors only appear once a field has been visited or a save has been attempted — a form that
/// is red before you have typed anything reads as broken rather than helpful.
struct GroupFormView: View {

    @Binding var draft: GroupFormDraft
    /// Participants who appear on an expense; the server refuses to remove these.
    var participantsWithExpenses: Set<String> = []
    var isSaving: Bool
    let saveTitle: LocalizedStringKey
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var hasAttemptedSave = false
    @State private var blockedParticipant: String?
    @FocusState private var focusedParticipant: ParticipantDraft.ID?

    var body: some View {
        Form {
            Section {
                TextField("Group name", text: $draft.name)
                    .accessibilityIdentifier(AccessibilityID.GroupForm.nameField)
                problemLabel(for: [.nameTooShort, .nameTooLong])

                TextField("Currency symbol", text: $draft.currency)
                    .accessibilityIdentifier(AccessibilityID.GroupForm.currencyField)
                problemLabel(for: [.currencyMissing, .currencyTooLong])
            } header: {
                Text("Group information")
            } footer: {
                Text("The currency symbol is shown next to every amount, for example $ or CHF.")
            }

            Section("Notes") {
                TextField(
                    "What should participants know?",
                    text: $draft.information,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .accessibilityIdentifier(AccessibilityID.GroupForm.informationField)
            }

            Section {
                ForEach(Array($draft.participants.enumerated()), id: \.element.id) { index, $participant in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $participant.name)
                            .focused($focusedParticipant, equals: participant.id)
                            .accessibilityIdentifier(
                                AccessibilityID.GroupForm.participantField(index)
                            )

                        if hasAttemptedSave,
                           let problem = draft.problems(forParticipant: participant.id).first {
                            Text(problem.message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            remove(participant)
                        }
                    }
                }

                Button("Add participant", systemImage: "person.badge.plus") {
                    let participant = ParticipantDraft()
                    draft.participants.append(participant)
                    focusedParticipant = participant.id
                }
                .accessibilityIdentifier(AccessibilityID.GroupForm.addParticipantButton)
            } header: {
                Text("Participants")
            } footer: {
                if hasAttemptedSave, draft.problems.contains(.noParticipants) {
                    Text(GroupFormDraft.Problem.noParticipants.message)
                        .foregroundStyle(.red)
                } else {
                    Text("Swipe a participant to remove them. Anyone who already appears on an expense can’t be removed.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier(AccessibilityID.GroupForm.cancelButton)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveTitle) {
                    hasAttemptedSave = true
                    guard draft.isValid else { return }
                    onSave()
                }
                .disabled(isSaving)
                .accessibilityIdentifier(AccessibilityID.GroupForm.saveButton)
            }
        }
        .alert(
            "This participant has expenses",
            isPresented: Binding(
                get: { blockedParticipant != nil },
                set: { if !$0 { blockedParticipant = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(blockedParticipant ?? "") appears on at least one expense, so they can’t be removed. Delete or reassign those expenses first.")
        }
    }

    private func remove(_ participant: ParticipantDraft) {
        if let serverID = participant.serverID, participantsWithExpenses.contains(serverID) {
            blockedParticipant = participant.name
            return
        }
        draft.participants.removeAll { $0.id == participant.id }
    }

    @ViewBuilder
    private func problemLabel(for candidates: [GroupFormDraft.Problem]) -> some View {
        if hasAttemptedSave, let problem = draft.problems.first(where: candidates.contains) {
            Text(problem.message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.GroupForm.error)
        }
    }
}

/// "Create group", presented as a sheet from the group list.
struct CreateGroupView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var draft = GroupFormDraft()
    @State private var isSaving = false
    @State private var failure: String?

    /// Called with the new group so the caller can remember it and open it.
    let onCreated: (RecentGroup) -> Void

    var body: some View {
        NavigationStack {
            GroupFormView(
                draft: $draft,
                isSaving: isSaving,
                saveTitle: "Create",
                onSave: save,
                onCancel: { dismiss() }
            )
            .navigationTitle("Create group")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.createGroup)
            .alert("Couldn’t create the group", isPresented: .constant(failure != nil)) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let response = try await app.client.call(Spliit.createGroup(draft.formValues))
                Analytics.shared.event(.createGroup)
                onCreated(
                    RecentGroup(groupId: response.groupId, groupName: draft.formValues.name)
                )
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// "Group settings" — the same form, loaded from the server so participant IDs survive.
struct GroupSettingsView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let groupID: String
    let onSaved: (String) -> Void

    @State private var draft: GroupFormDraft?
    @State private var participantsWithExpenses: Set<String> = []
    @State private var isSaving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    GroupFormView(
                        draft: Binding(get: { draft }, set: { self.draft = $0 }),
                        participantsWithExpenses: participantsWithExpenses,
                        isSaving: isSaving,
                        saveTitle: "Save",
                        onSave: save,
                        onCancel: { dismiss() }
                    )
                } else if failure != nil {
                    ContentUnavailableView(
                        "Couldn’t load the group",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure ?? "")
                    )
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle("Group settings")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.groupSettings, properties: ["groupId": groupID])
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let response = try await app.client.call(Spliit.groupDetails(id: groupID))
            draft = GroupFormDraft(editing: response.group)
            participantsWithExpenses = Set(response.participantsWithExpenses)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func save() {
        guard let draft else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await app.client.call(
                    Spliit.updateGroup(id: groupID, values: draft.formValues)
                )
                onSaved(draft.formValues.name)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
