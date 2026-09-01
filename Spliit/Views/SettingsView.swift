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
