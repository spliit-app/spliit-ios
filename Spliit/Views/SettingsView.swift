import SwiftUI

/// The about information the old app kept here, and the version.
///
/// No server address any more: an instance belongs to a group, not to the app, so it is chosen
/// when a group is created and read from the link when one is added. A single setting here could
/// only ever be wrong for every group that isn't on it.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Settings.doneButton)
                }
            }
        }
        .trackScreen(.about)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
