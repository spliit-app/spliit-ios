import SpliitAPI
import SpliitCore
import SwiftUI

/// What a group *is*, beside what it costs: the note it keeps for its participants, who those
/// participants are, and the couple of facts that until now were only visible from inside the
/// editor.
///
/// The web app's version of this tab is the note and nothing else. That reads differently on a
/// phone, where a tab is one of a handful of places a thumb can reach and most groups never fill
/// the note in — the tab would be empty for exactly the people who went looking. Naming the
/// participants is the cheapest thing that earns the slot, and this is the only screen in the app
/// that lists them outside the editor.
///
/// The note has no editor of its own and should not grow one: it is a field on the group, and the
/// group form is where the group's fields are edited.
struct GroupInformationView: View {

    @Environment(AppModel.self) private var app
    let model: GroupDetailModel
    /// Opens group settings, where the note actually lives.
    let onEdit: () -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        // Everything here is the group, so unlike the expense and balance tabs there is no second
        // request to wait on and nothing to draw while the first one is out.
        if model.isLoadingGroup {
            ProgressView().controlSize(.large)
        } else if model.didFailToLoad {
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text("Couldn’t load this group"),
                description: Text(
                    model.loadFailure ?? String(localized: "The server didn’t respond.")
                )
            ) {
                Button("Try again") {
                    Task { await model.retry(using: app.client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.GroupInformation.retryButton)
            }
        } else if let group = model.group {
            List {
                noteSection(for: group)
                participantsSection(for: group)
                detailsSection(for: group)
            }
            // `reload` rather than the other tabs' `reloadAfterExpenseChange`: the group itself
            // is what this screen shows, and that is the one thing an expense-shaped refresh
            // deliberately leaves alone.
            .refreshable { await model.reload(using: app.client) }
        }
    }

    private func noteSection(for group: SpliitAPI.Group) -> some View {
        let note = trimmedInformation(of: group)

        return Section {
            if let note {
                Text(note)
                    // What people put here is a meeting point, an IBAN, a link — things that are
                    // written down in order to be copied back out.
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.GroupInformation.note)
            } else {
                Text("No information yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.GroupInformation.empty)
            }

            Button(
                note == nil ? "Add information" : "Edit information",
                systemImage: "square.and.pencil",
                action: onEdit
            )
            .accessibilityIdentifier(AccessibilityID.GroupInformation.editButton)
        } header: {
            Text("Information")
        } footer: {
            Text("Anything the group should know — where you are staying, how the split works, a link. Everyone who opens the group sees it.")
        }
    }

    private func participantsSection(for group: SpliitAPI.Group) -> some View {
        Section {
            ForEach(Array(group.participants.enumerated()), id: \.element.id) { position, participant in
                HStack(spacing: 10) {
                    // Coloured by position, which is what makes someone the same colour here as
                    // on the balances and on every expense they paid for.
                    Monogram(name: participant.name, position: position, size: 26)

                    Text(participant.name)
                        .accessibilityIdentifier(
                            AccessibilityID.GroupInformation.participant(participant.id)
                        )
                }
            }
        } header: {
            Text("Participants")
        } footer: {
            Text("Add or remove participants in the group settings.")
        }
    }

    private func detailsSection(for group: SpliitAPI.Group) -> some View {
        Section("Details") {
            LabeledContent("Currency") {
                Text(currencyDescription(of: group))
                    .accessibilityIdentifier(AccessibilityID.GroupInformation.currency)
            }

            LabeledContent("Created") {
                Text(group.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    /// The note, or nothing at all. The server stores whatever was typed, and a note of three
    /// spaces is not a note — it would draw a blank row where the empty state belongs.
    private func trimmedInformation(of group: SpliitAPI.Group) -> String? {
        let trimmed = group.information?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The symbol, with the ISO code beside it when the group has one: "$" on its own does not
    /// say whether the group counts in dollars, pesos or something else again.
    private func currencyDescription(of group: SpliitAPI.Group) -> String {
        guard let code = group.currencyCode, !code.isEmpty else { return group.currency }
        return "\(group.currency) (\(code))"
    }
}
