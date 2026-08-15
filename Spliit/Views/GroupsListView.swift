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
    @State private var path: [String] = []
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case settings, createGroup, addByURL
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Groups")
                .navigationDestination(for: String.self) { groupID in
                    GroupDetailView(groupID: groupID)
                }
                .toolbar { toolbarContent }
                .sheet(item: $sheet, content: sheetContent)
                .trackScreen(.home)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { sheet = .settings }
                .accessibilityIdentifier(AccessibilityID.GroupsList.settingsButton)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Create group", systemImage: "plus") { sheet = .createGroup }
                    .accessibilityIdentifier(AccessibilityID.GroupsList.createGroupButton)
                Button("Add by link", systemImage: "link") { sheet = .addByURL }
                    .accessibilityIdentifier(AccessibilityID.GroupsList.addByURLButton)
            } label: {
                Label("Add group", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .createGroup:
            CreateGroupView { group in
                app.recentGroups.remember(group)
                path = [group.groupId]
            }
        case .addByURL:
            AddGroupByURLView { group in
                app.recentGroups.remember(group)
            }
        }
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
        EmptyState(
            art: .logo,
            title: Text("Welcome to Spliit"),
            description: Text("Create a group to start splitting expenses with friends, or add one that was shared with you.")
        ) {
            VStack(spacing: 12) {
                Button("Create group") { sheet = .createGroup }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.GroupsList.createGroupButton)

                Button("Add group by link") { sheet = .addByURL }
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
                    NavigationLink(value: group.groupId) {
                        GroupRow(group: group, summary: model.summaries[group.groupId])
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            app.recentGroups.forget(groupId: group.groupId)
                        }
                        // Read on its own, "Remove" sounds like it deletes the group. It only
                        // forgets it here, and there is no way back but the link.
                        .accessibilityLabel(
                            Text("Remove \(group.groupName) from this list")
                        )
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
        AdaptiveHStack(verticalAlignment: .top, spacing: 12) {
            // A group is the app's top-level object and used to be the plainest thing on screen.
            // Seeding on the ID rather than the name keeps a group's colour across a rename.
            Monogram(name: group.groupName, seed: group.groupId, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName)
                    .font(.system(.headline, design: .rounded))
                    .accessibilityIdentifier(AccessibilityID.GroupsList.rowTitle(group.groupId))

                AdaptiveHStack(spacing: 12) {
                    Label(participantText, systemImage: "person.2")
                        .accessibilityIdentifier(
                            AccessibilityID.GroupsList.rowParticipants(group.groupId)
                        )
                    if let createdAt = summary?.createdAt {
                        Label(createdAt.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .accessibilityLabel(
                                Text("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
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
