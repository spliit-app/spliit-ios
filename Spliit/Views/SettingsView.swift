import SpliitCore
import SwiftUI

/// Which Spliit instance to talk to, plus the about information the old app kept here.
struct SettingsView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var addressText = ""
    @State private var isAddressValid = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://spliit.app/", text: $addressText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(commitAddress)
                        .accessibilityIdentifier(AccessibilityID.Settings.baseURLField)

                    if !isAddressValid {
                        Text("That doesn’t look like a web address. Try something like spliit.example.com.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !app.settings.isUsingOfficialInstance {
                        Button("Use spliit.app") {
                            app.settings.resetToOfficialInstance()
                            addressText = app.settings.baseURL.absoluteString
                            isAddressValid = true
                        }
                        .accessibilityIdentifier(AccessibilityID.Settings.resetButton)
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Point the app at your own Spliit instance. Leave this alone if you use the official one.")
                }

                Section {
                    Link("Visit spliit.app", destination: URL(string: "https://spliit.app/?ref=ios-app")!)
                    Link("View on GitHub", destination: URL(string: "https://github.com/spliit-app")!)
                } header: {
                    Text("About")
                } footer: {
                    Text("Spliit is an open source project by Sebastien Castiel, with help from many contributors.")
                }

                // A permanent way in, so that being asked is never the only one. The prompt
                // itself is deliberately rare — see `ReviewPromptStore` — and somebody who
                // wants to say something today should not have to wait for it.
                Section {
                    Link(
                        "Rate Spliit on the App Store",
                        destination: URL(
                            string: "https://apps.apple.com/app/id6737742507?action=write-review"
                        )!
                    )
                    .accessibilityIdentifier(AccessibilityID.Settings.rateButton)

                    Link(
                        "Report a problem",
                        destination: URL(string: "https://github.com/spliit-app/spliit-ios/issues")!
                    )
                    .accessibilityIdentifier(AccessibilityID.Settings.feedbackButton)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("A review is how people find an app nobody advertises. Anything that is wrong with this one is better raised on GitHub, where it can be fixed.")
                }

                Section {
                    LabeledContent("Version", value: versionText)
                        .accessibilityIdentifier(AccessibilityID.Settings.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitAddress()
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.Settings.doneButton)
                }
            }
        }
        .trackScreen(.about)
        .onAppear {
            addressText = app.settings.baseURL.absoluteString
        }
    }

    private func commitAddress() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            app.settings.resetToOfficialInstance()
            addressText = app.settings.baseURL.absoluteString
            isAddressValid = true
            return
        }
        guard let url = SettingsStore.normalize(trimmed) else {
            isAddressValid = false
            return
        }
        app.settings.baseURL = url
        addressText = url.absoluteString
        isAddressValid = true
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
