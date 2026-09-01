import SpliitCore
import SwiftUI

/// Which Spliit instance a new group is created on.
///
/// Every instance the list already uses is offered, because the common case by far is another
/// group on a server somebody already has. "Other server" is the way in for the first group on a
/// new one, and it is the only place in the app where an address is typed rather than pasted.
struct InstanceField: View {

    @Binding var choice: InstanceChoice
    let knownInstances: [URL]
    /// Whether a save has already been attempted — the form's rule for when a problem is worth
    /// pointing out, so an address that is merely half-typed isn't called wrong.
    let showsProblem: Bool

    var body: some View {
        Picker("Server", selection: selection) {
            ForEach(knownInstances, id: \.self) { url in
                Text(SettingsStore.displayName(for: url)).tag(URL?.some(url))
            }
            Text("Other server").tag(URL?.none)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(AccessibilityID.GroupForm.serverPicker)

        if choice.isTypingAddress {
            TextField("spliit.example.com", text: $choice.address)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.GroupForm.serverField)

            if showsProblem, !choice.isValid {
                Text("That doesn’t look like a web address. Try something like spliit.example.com.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityID.GroupForm.serverError)
            }
        }
    }

    /// Nil is "Other server": the picker has no URL to stand for an address that hasn't been
    /// typed yet.
    private var selection: Binding<URL?> {
        Binding(
            get: { choice.isTypingAddress ? nil : choice.url },
            set: { picked in
                if let picked {
                    choice.use(picked)
                } else {
                    choice.typeAddress()
                }
            }
        )
    }
}
