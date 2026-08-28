import SpliitAPI
import SpliitCore
import SwiftUI

/// "Who are you in this group?" — asked once per group, answered locally.
///
/// The web app asks this in a modal the first time a group is opened. This one is never
/// presented on its own: a sheet in front of a group somebody just tapped into is a toll gate on
/// the way to the expenses they asked for, and the question only pays off on the balances tab —
/// which is where it is offered, beside the answer it unlocks.
struct ActiveUserPickerView: View {

    let group: SpliitAPI.Group
    /// What is stored now, already resolved against the group's participants.
    let selection: ActiveParticipant?
    let onSelect: (ActiveParticipant) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(group.participants.enumerated()), id: \.element.id) { position, participant in
                        row(for: participant, position: position)
                    }
                } footer: {
                    Text("This stays on this phone. Spliit has no accounts, so nobody else in the group can see which participant you picked.")
                }

                Section {
                    nobodyRow
                } footer: {
                    Text("Pick nobody on a phone the whole group shares.")
                }
            }
            .navigationTitle("Who are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Short enough to be a card rather than a screen: a group is a handful of people, and
        // the question is one tap of an answer.
        .presentationDetents([.medium, .large])
    }

    private func row(for participant: Participant, position: Int) -> some View {
        let isSelected = selection?.participantID == participant.id

        return Button {
            choose(.participant(participant.id))
        } label: {
            HStack(spacing: 12) {
                Monogram(name: participant.name, position: position, size: 28)

                Text(participant.name)

                Spacer(minLength: 8)

                checkmark(isSelected: isSelected)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(AccessibilityID.ActiveUser.option(participant.id))
    }

    private var nobodyRow: some View {
        let isSelected = selection == .nobody

        return Button {
            choose(.nobody)
        } label: {
            HStack(spacing: 12) {
                Text("Nobody")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                checkmark(isSelected: isSelected)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(AccessibilityID.ActiveUser.nobodyOption)
    }

    @ViewBuilder
    private func checkmark(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                // The trait on the row is what says "selected"; the tick is how it looks.
                .accessibilityHidden(true)
        }
    }

    private func choose(_ participant: ActiveParticipant) {
        onSelect(participant)
        dismiss()
    }
}

#Preview {
    ActiveUserPickerView(
        group: SpliitAPI.Group(
            id: "preview",
            name: "Lisbon",
            information: nil,
            currency: "$",
            currencyCode: "USD",
            createdAt: .now,
            participants: [
                Participant(id: "1", name: "Ana"),
                Participant(id: "2", name: "Bruno"),
                Participant(id: "3", name: "Chidi"),
            ]
        ),
        selection: .participant("2"),
        onSelect: { _ in }
    )
}
