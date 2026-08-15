import SpliitAPI
import SpliitCore
import SwiftUI

/// The home screen: the groups this device remembers, with participant counts and dates
/// fetched from the instance.
///
/// The list itself is local — Spliit has no accounts — so it renders immediately and the
/// server details fill in. A server that can't be reached costs detail, not the list.
struct GroupsListView: View {

    @Environment(AppModel.self) private var app
    @State private var model = GroupsListModel()
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Groups")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") {
                            isShowingSettings = true
                        }
                        .accessibilityIdentifier(AccessibilityID.GroupsList.settingsButton)
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                }
        }
        .task(id: reloadToken) {
            await model.load(ids: app.recentGroups.groups.map(\.groupId), using: app.client)
        }
    }

    /// Reloads when the remembered groups change, or when the instance is switched.
    private var reloadToken: String {
        app.recentGroups.groups.map(\.groupId).joined(separator: ",")
            + "@" + app.settings.baseURL.absoluteString
    }

    @ViewBuilder
    private var content: some View {
        if app.recentGroups.groups.isEmpty {
            emptyState
        } else {
            groupList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to Spliit", systemImage: "person.2")
        } description: {
            Text("Create a group to start splitting expenses with friends, or add one that was shared with you.")
        } actions: {
            VStack(spacing: 12) {
                Button("Create group") {}
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.GroupsList.createGroupButton)

                Button("Add group by URL") {}
                    .accessibilityIdentifier(AccessibilityID.GroupsList.addByURLButton)
            }
        }
    }

    private var groupList: some View {
        List {
            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .accessibilityIdentifier(AccessibilityID.GroupsList.loadFailed)
                }
            }

            Section("Recent groups") {
                ForEach(app.recentGroups.groups) { group in
                    GroupRow(group: group, summary: model.summaries[group.groupId])
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                app.recentGroups.forget(groupId: group.groupId)
                            }
                        }
                }
            }
        }
        .refreshable {
            await model.load(
                ids: app.recentGroups.groups.map(\.groupId), using: app.client
            )
        }
    }
}

private struct GroupRow: View {
    let group: RecentGroup
    let summary: GroupSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.groupName)
                .font(.headline)
                .accessibilityIdentifier(AccessibilityID.GroupsList.rowTitle(group.groupId))

            HStack(spacing: 12) {
                Label(participantText, systemImage: "person.2")
                    .accessibilityIdentifier(
                        AccessibilityID.GroupsList.rowParticipants(group.groupId)
                    )
                if let createdAt = summary?.createdAt {
                    Label(createdAt.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var participantText: String {
        guard let count = summary?.participantCount else { return "…" }
        return count == 1 ? "1 participant" : "\(count) participants"
    }
}

/// Fetches the server-side detail for the remembered groups.
@Observable
final class GroupsListModel {

    private(set) var summaries: [String: GroupSummary] = [:]
    private(set) var errorMessage: String?

    func load(ids: [String], using client: TRPCClient) async {
        guard !ids.isEmpty else {
            summaries = [:]
            errorMessage = nil
            return
        }

        do {
            let response = try await client.call(Spliit.groups(ids: ids))
            summaries = Dictionary(uniqueKeysWithValues: response.groups.map { ($0.id, $0) })
            errorMessage = nil
        } catch {
            // The names are stored locally, so the list is still usable — say what's missing
            // rather than replacing everything with an error screen.
            errorMessage = String(
                localized: "Couldn’t reach the server, so group details may be out of date."
            )
        }
    }
}
