import SpliitAPI
import SpliitCore
import SwiftUI

/// Adds a group someone shared, by pasting its URL.
///
/// Spliit has no accounts: a group URL *is* the invitation, so this is how a second device
/// ever learns about a group.
struct AddGroupByURLView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let onAdded: (RecentGroup) -> Void

    @State private var urlText = ""
    @State private var isChecking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("\(app.settings.baseURL.absoluteString)groups/…", text: $urlText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                        .accessibilityIdentifier(AccessibilityID.AddByURL.field)

                    if let problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(AccessibilityID.AddByURL.error)
                    }
                } header: {
                    Text("Group link")
                } footer: {
                    Text("Paste the link to a group that was shared with you, and it will appear in your list.")
                }
            }
            .navigationTitle("Add group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.AddByURL.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChecking ? "Adding…" : "Add", action: add)
                        .disabled(isChecking || urlText.isEmpty)
                        .accessibilityIdentifier(AccessibilityID.AddByURL.addButton)
                }
            }
            .trackScreen(.addGroupByURL)
        }
    }

    private func add() {
        guard !isChecking else { return }
        problem = nil

        guard let groupID = GroupLink.groupID(inPastedText: urlText) else {
            problem = String(localized: "That doesn’t look like a Spliit group link.")
            return
        }

        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let response = try await app.client.call(Spliit.group(id: groupID))
                guard let group = response.group else {
                    problem = String(
                        localized: "No group with that link exists on this server."
                    )
                    return
                }
                onAdded(RecentGroup(groupId: group.id, groupName: group.name))
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
